import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/application/services/metrics_collector.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/domain/constants/transfer_lease.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_progress_snapshot.dart';
import 'package:backup_database/domain/entities/execution_origin.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_backup_running_state.dart';
import 'package:backup_database/domain/services/i_file_transfer_lock_service.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_send_file_to_destination_service.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/domain/use_cases/scheduling/update_schedule.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/queue_events.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/server/execution_event_sequencer.dart';
import 'package:backup_database/infrastructure/socket/server/execution_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/execution_status_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/file_transfer_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/metrics_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/queue_event_bus.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_telemetry.dart';
import 'package:backup_database/infrastructure/socket/server/socket_telemetry_constants.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;
import 'package:uuid/uuid.dart';

import '../helpers/stub_temp_directory_service.dart';

class _MockBackupDestinationRepository extends Mock
    implements IBackupDestinationRepository {}

class _MockSendFileToDestinationService extends Mock
    implements ISendFileToDestinationService {}

class _MockMachineSettingsRepository extends Mock
    implements IMachineSettingsRepository {}

class _MockFileTransferLockService implements IFileTransferLockService {
  @override
  Future<bool> tryAcquireLock(
    String filePath, {
    String owner = 'unknown',
    String? runId,
    Duration leaseTtl = kDefaultTransferLeaseTtl,
  }) async => true;

  @override
  Future<void> releaseLock(String filePath) async {}

  @override
  Future<bool> isLocked(String filePath) async => false;

  @override
  Future<void> cleanupExpiredLocks({
    Duration maxAge = kDefaultTransferLeaseTtl,
  }) async {}
}

int _nextE2ePort = 29850;

int _e2ePort() {
  final port = _nextE2ePort;
  _nextE2ePort++;
  return port;
}

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

class _MockBackupHistoryRepository extends Mock
    implements IBackupHistoryRepository {}

class _MockBackupRunningState extends Mock implements IBackupRunningState {}

class _MockLicensePolicyService extends Mock implements ILicensePolicyService {}

class _MockSchedulerService extends Mock implements ISchedulerService {}

class _MockUpdateSchedule extends Mock implements UpdateSchedule {}

class _MockExecuteBackup extends Mock implements ExecuteScheduledBackup {}

class _MockProgressNotifier extends Mock implements IBackupProgressNotifier {}

typedef _RemoteE2eSocket = ({
  TcpSocketServer server,
  ConnectionManager manager,
  String clientId,
  Directory serverDir,
});

typedef _StartBackupE2eEnv = ({
  TcpSocketServer server,
  ScheduleMessageHandler scheduleHandler,
  Directory serverDir,
  String artifactPath,
  String scheduleId,
  int port,
});

typedef _QueueDrainE2eEnv = ({
  TcpSocketServer server,
  ScheduleMessageHandler scheduleHandler,
  Directory serverDir,
  String artifactPath,
  int port,
  Completer<rd.Result<bool>> blockFirstBackup,
  BackupProgressProvider progressNotifier,
  int Function() executeCallCount,
});

typedef _DeepQueueE2eEnv = ({
  TcpSocketServer server,
  ScheduleMessageHandler scheduleHandler,
  Directory serverDir,
  String artifactPath,
  int port,
  Completer<rd.Result<bool>> releaseFirstBackup,
  BackupProgressProvider progressNotifier,
  ExecutionMessageHandler executionHandler,
  List<String> executionOrder,
  void Function(bool isBusy) setSchedulerBusy,
});

const _e2eScheduleId = 'sch-e2e-start-backup';

final _e2eSchedule = Schedule(
  id: _e2eScheduleId,
  name: 'E2E Remote Backup',
  databaseConfigId: 'db-e2e',
  databaseType: DatabaseType.sqlServer,
  scheduleType: ScheduleType.daily.name,
  scheduleConfig: '{}',
  destinationIds: const ['dest-e2e'],
  backupFolder: r'C:\backup',
);

Schedule _e2eScheduleWithId(String id) => Schedule(
  id: id,
  name: 'E2E $id',
  databaseConfigId: 'db-e2e',
  databaseType: DatabaseType.sqlServer,
  scheduleType: ScheduleType.daily.name,
  scheduleConfig: '{}',
  destinationIds: const ['dest-e2e'],
  backupFolder: r'C:\backup',
);

Future<_StartBackupE2eEnv> _startStartBackupE2eServer({
  required String artifactContent,
  bool schedulerBusy = false,
}) async {
  final serverDir = await Directory.systemTemp.createTemp('re_exec_srv_');
  const artifactName = 'start-backup-artifact.bin';
  final artifactFile = File(p.join(serverDir.path, artifactName));
  await artifactFile.writeAsString(artifactContent);
  final artifactPath = p.normalize(artifactFile.path);

  final scheduleRepository = _MockScheduleRepository();
  when(
    () => scheduleRepository.getById(_e2eScheduleId),
  ).thenAnswer((_) async => rd.Success(_e2eSchedule));
  when(
    scheduleRepository.getEnabled,
  ).thenAnswer((_) async => rd.Success(<Schedule>[_e2eSchedule]));

  final licensePolicyService = _MockLicensePolicyService();
  when(
    () => licensePolicyService.validateExecutionCapabilities(any(), any()),
  ).thenAnswer((_) async => const rd.Success(true));

  final schedulerService = _MockSchedulerService();
  when(() => schedulerService.isExecutingBackup).thenReturn(schedulerBusy);

  final executeBackup = _MockExecuteBackup();
  final progressNotifier = BackupProgressProvider();
  final registry = RemoteExecutionRegistry();
  final sequencer = ExecutionEventSequencer();

  when(
    () => executeBackup(
      _e2eScheduleId,
      executionOrigin: ExecutionOrigin.remoteCommand,
    ),
  ).thenAnswer((_) async {
    // Aguarda o cliente registrar `_activeBackupsByRunId` após
    // `startRemoteBackup` — o mock conclui sincronamente sem isso.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    progressNotifier.completeBackup(
      message: 'Backup concluído',
      backupPath: artifactPath,
    );
    return const rd.Success(true);
  });

  final scheduleHandler = ScheduleMessageHandler(
    scheduleRepository: scheduleRepository,
    licensePolicyService: licensePolicyService,
    schedulerService: schedulerService,
    updateSchedule: _MockUpdateSchedule(),
    executeBackup: executeBackup,
    progressNotifier: progressNotifier,
    executionRegistry: registry,
    eventSequencer: sequencer,
  );

  final executionHandler = ExecutionMessageHandler(
    scheduleRepository: scheduleRepository,
    licensePolicyService: licensePolicyService,
    schedulerService: schedulerService,
    executeBackup: executeBackup,
    progressNotifier: progressNotifier,
    executionRegistry: registry,
    eventSequencer: sequencer,
    stagingUsageBytesProvider: () async => 0,
  );

  final backupHistoryRepository = _MockBackupHistoryRepository();
  when(
    () => backupHistoryRepository.getAll(limit: any(named: 'limit')),
  ).thenAnswer((_) async => const rd.Success(<BackupHistory>[]));
  when(
    () => backupHistoryRepository.getByDateRange(any(), any()),
  ).thenAnswer((_) async => const rd.Success(<BackupHistory>[]));

  final backupRunningState = _MockBackupRunningState();
  when(() => backupRunningState.isRunning).thenReturn(false);
  when(() => backupRunningState.currentBackupName).thenReturn(null);

  final metricsCollector = MetricsCollector();
  final socketTelemetry = SocketServerTelemetry(
    metricsCollector: metricsCollector,
  );
  final metricsHandler = MetricsMessageHandler(
    backupHistoryRepository: backupHistoryRepository,
    scheduleRepository: scheduleRepository,
    backupRunningState: backupRunningState,
    metricsCollector: metricsCollector,
    socketTelemetry: socketTelemetry,
    executionRegistry: registry,
    queueService: executionHandler.queueService,
  );

  final executionStatusHandler = ExecutionStatusMessageHandler(
    executionRegistry: registry,
    queueService: executionHandler.queueService,
  );

  final fileTransferHandler = FileTransferMessageHandler(
    allowedBasePath: serverDir.path,
    lockService: _MockFileTransferLockService(),
  );

  final executionQueueHandler = ExecutionQueueMessageHandler(
    queueProvider: () async => executionHandler.queueService.snapshot(),
  );

  final server = TcpSocketServer(
    scheduleHandler: scheduleHandler,
    executionHandler: executionHandler,
    fileTransferHandler: fileTransferHandler,
    metricsHandler: metricsHandler,
    executionStatusHandler: executionStatusHandler,
    executionQueueHandler: executionQueueHandler,
    socketTelemetry: socketTelemetry,
  );
  executionHandler.eventBus = QueueEventBus(
    broadcast: server.sendToClient,
    sequencer: sequencer,
  );

  final port = _e2ePort();
  await server.start(port: port);

  return (
    server: server,
    scheduleHandler: scheduleHandler,
    serverDir: serverDir,
    artifactPath: artifactPath,
    scheduleId: _e2eScheduleId,
    port: port,
  );
}

Future<_QueueDrainE2eEnv> _startQueueDrainE2eServer({
  required String artifactContent,
}) async {
  final blockFirstBackup = Completer<rd.Result<bool>>();
  final serverDir = await Directory.systemTemp.createTemp('re_exec_q_');
  const artifactName = 'queue-drain-artifact.bin';
  final artifactFile = File(p.join(serverDir.path, artifactName));
  await artifactFile.writeAsString(artifactContent);
  final artifactPath = p.normalize(artifactFile.path);

  final scheduleRepository = _MockScheduleRepository();
  when(
    () => scheduleRepository.getById(_e2eScheduleId),
  ).thenAnswer((_) async => rd.Success(_e2eSchedule));
  when(
    scheduleRepository.getEnabled,
  ).thenAnswer((_) async => rd.Success(<Schedule>[_e2eSchedule]));

  final licensePolicyService = _MockLicensePolicyService();
  when(
    () => licensePolicyService.validateExecutionCapabilities(any(), any()),
  ).thenAnswer((_) async => const rd.Success(true));

  final schedulerService = _MockSchedulerService();
  when(() => schedulerService.isExecutingBackup).thenReturn(false);

  final executeBackup = _MockExecuteBackup();
  final progressNotifier = BackupProgressProvider();
  final registry = RemoteExecutionRegistry();
  final sequencer = ExecutionEventSequencer();
  var executeCalls = 0;

  when(
    () => executeBackup(
      _e2eScheduleId,
      executionOrigin: ExecutionOrigin.remoteCommand,
    ),
  ).thenAnswer((_) async {
    executeCalls++;
    if (executeCalls == 1) {
      final result = await blockFirstBackup.future;
      if (result.isSuccess()) {
        progressNotifier.completeBackup(
          message: 'Backup enfileirado concluído',
          backupPath: artifactPath,
        );
      }
      return result;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    progressNotifier.completeBackup(
      message: 'Backup enfileirado concluído',
      backupPath: artifactPath,
    );
    return const rd.Success(true);
  });

  final scheduleHandler = ScheduleMessageHandler(
    scheduleRepository: scheduleRepository,
    licensePolicyService: licensePolicyService,
    schedulerService: schedulerService,
    updateSchedule: _MockUpdateSchedule(),
    executeBackup: executeBackup,
    progressNotifier: progressNotifier,
    executionRegistry: registry,
    eventSequencer: sequencer,
  );

  final executionHandler = ExecutionMessageHandler(
    scheduleRepository: scheduleRepository,
    licensePolicyService: licensePolicyService,
    schedulerService: schedulerService,
    executeBackup: executeBackup,
    progressNotifier: progressNotifier,
    executionRegistry: registry,
    eventSequencer: sequencer,
    stagingUsageBytesProvider: () async => 0,
  );

  final executionStatusHandler = ExecutionStatusMessageHandler(
    executionRegistry: registry,
    queueService: executionHandler.queueService,
  );

  final executionQueueHandler = ExecutionQueueMessageHandler(
    queueProvider: () async => executionHandler.queueService.snapshot(),
  );

  final server = TcpSocketServer(
    scheduleHandler: scheduleHandler,
    executionHandler: executionHandler,
    executionStatusHandler: executionStatusHandler,
    executionQueueHandler: executionQueueHandler,
    fileTransferHandler: FileTransferMessageHandler(
      allowedBasePath: serverDir.path,
      lockService: _MockFileTransferLockService(),
    ),
  );
  executionHandler.eventBus = QueueEventBus(
    broadcast: server.sendToClient,
    sequencer: sequencer,
  );

  final port = _e2ePort();
  await server.start(port: port);

  return (
    server: server,
    scheduleHandler: scheduleHandler,
    serverDir: serverDir,
    artifactPath: artifactPath,
    port: port,
    blockFirstBackup: blockFirstBackup,
    progressNotifier: progressNotifier,
    executeCallCount: () => executeCalls,
  );
}

Future<_DeepQueueE2eEnv> _startDeepQueueE2eServer({
  required String artifactContent,
}) async {
  final releaseFirstBackup = Completer<rd.Result<bool>>();
  final serverDir = await Directory.systemTemp.createTemp('re_exec_deep_q_');
  const artifactName = 'deep-queue-artifact.bin';
  final artifactFile = File(p.join(serverDir.path, artifactName));
  await artifactFile.writeAsString(artifactContent);
  final artifactPath = p.normalize(artifactFile.path);

  final scheduleRepository = _MockScheduleRepository();
  when(() => scheduleRepository.getById(any())).thenAnswer((invocation) async {
    final id = invocation.positionalArguments[0] as String;
    return rd.Success(_e2eScheduleWithId(id));
  });
  when(
    scheduleRepository.getEnabled,
  ).thenAnswer((_) async => const rd.Success(<Schedule>[]));

  final licensePolicyService = _MockLicensePolicyService();
  when(
    () => licensePolicyService.validateExecutionCapabilities(any(), any()),
  ).thenAnswer((_) async => const rd.Success(true));

  final schedulerService = _MockSchedulerService();
  var schedulerReportsBusy = true;
  when(() => schedulerService.isExecutingBackup).thenAnswer((_) {
    return schedulerReportsBusy;
  });

  final executeBackup = _MockExecuteBackup();
  final progressNotifier = BackupProgressProvider();
  final registry = RemoteExecutionRegistry();
  final sequencer = ExecutionEventSequencer();
  final executionOrder = <String>[];

  when(
    () => executeBackup(
      any(),
      executionOrigin: any(named: 'executionOrigin'),
    ),
  ).thenAnswer((invocation) async {
    final scheduleId = invocation.positionalArguments[0] as String;
    executionOrder.add(scheduleId);
    if (executionOrder.length == 1) {
      await releaseFirstBackup.future;
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    progressNotifier.completeBackup(
      message: 'OK',
      backupPath: artifactPath,
    );
    return const rd.Success(true);
  });

  final scheduleHandler = ScheduleMessageHandler(
    scheduleRepository: scheduleRepository,
    licensePolicyService: licensePolicyService,
    schedulerService: schedulerService,
    updateSchedule: _MockUpdateSchedule(),
    executeBackup: executeBackup,
    progressNotifier: progressNotifier,
    executionRegistry: registry,
    eventSequencer: sequencer,
  );

  final executionHandler = ExecutionMessageHandler(
    scheduleRepository: scheduleRepository,
    licensePolicyService: licensePolicyService,
    schedulerService: schedulerService,
    executeBackup: executeBackup,
    progressNotifier: progressNotifier,
    executionRegistry: registry,
    eventSequencer: sequencer,
    stagingUsageBytesProvider: () async => 0,
  );

  final executionStatusHandler = ExecutionStatusMessageHandler(
    executionRegistry: registry,
    queueService: executionHandler.queueService,
  );

  final executionQueueHandler = ExecutionQueueMessageHandler(
    queueProvider: () async => executionHandler.queueService.snapshot(),
  );

  final backupHistoryRepository = _MockBackupHistoryRepository();
  when(
    () => backupHistoryRepository.getAll(limit: any(named: 'limit')),
  ).thenAnswer((_) async => const rd.Success(<BackupHistory>[]));
  when(
    () => backupHistoryRepository.getByDateRange(any(), any()),
  ).thenAnswer((_) async => const rd.Success(<BackupHistory>[]));

  final backupRunningState = _MockBackupRunningState();
  when(() => backupRunningState.isRunning).thenReturn(false);
  when(() => backupRunningState.currentBackupName).thenReturn(null);

  final metricsCollector = MetricsCollector();
  final socketTelemetry = SocketServerTelemetry(
    metricsCollector: metricsCollector,
  );
  final metricsHandler = MetricsMessageHandler(
    backupHistoryRepository: backupHistoryRepository,
    scheduleRepository: scheduleRepository,
    backupRunningState: backupRunningState,
    metricsCollector: metricsCollector,
    socketTelemetry: socketTelemetry,
    executionRegistry: registry,
    queueService: executionHandler.queueService,
  );

  final server = TcpSocketServer(
    scheduleHandler: scheduleHandler,
    executionHandler: executionHandler,
    executionStatusHandler: executionStatusHandler,
    executionQueueHandler: executionQueueHandler,
    metricsHandler: metricsHandler,
    fileTransferHandler: FileTransferMessageHandler(
      allowedBasePath: serverDir.path,
      lockService: _MockFileTransferLockService(),
    ),
    socketTelemetry: socketTelemetry,
  );
  executionHandler.eventBus = QueueEventBus(
    broadcast: server.sendToClient,
    sequencer: sequencer,
  );

  final port = _e2ePort();
  await server.start(port: port);

  return (
    server: server,
    scheduleHandler: scheduleHandler,
    serverDir: serverDir,
    artifactPath: artifactPath,
    port: port,
    releaseFirstBackup: releaseFirstBackup,
    progressNotifier: progressNotifier,
    executionHandler: executionHandler,
    executionOrder: executionOrder,
    setSchedulerBusy: (bool busy) => schedulerReportsBusy = busy,
  );
}

Future<_RemoteE2eSocket> _connectRemoteExecutionE2eSocket() async {
  final serverDir = await Directory.systemTemp.createTemp('re_e2e_srv_');

  final fileTransferHandler = FileTransferMessageHandler(
    allowedBasePath: serverDir.path,
    lockService: _MockFileTransferLockService(),
  );
  final server = TcpSocketServer(fileTransferHandler: fileTransferHandler);
  final port = _e2ePort();
  await server.start(port: port);

  final manager = ConnectionManager();
  await manager.connect(host: '127.0.0.1', port: port);
  if (!manager.isConnected) {
    await server.stop();
    await manager.disconnect();
    await serverDir.delete(recursive: true);
    throw StateError('ConnectionManager failed to connect in E2E test');
  }

  final sessionResult = await manager.getServerSession();
  if (sessionResult.isError()) {
    await server.stop();
    await manager.disconnect();
    await serverDir.delete(recursive: true);
    throw StateError(
      'getServerSession failed: ${sessionResult.exceptionOrNull()}',
    );
  }
  final clientId = sessionResult.getOrNull()!.clientId;
  if (clientId.isEmpty) {
    await server.stop();
    await manager.disconnect();
    await serverDir.delete(recursive: true);
    throw StateError('empty clientId from getServerSession');
  }

  return (
    server: server,
    manager: manager,
    clientId: clientId,
    serverDir: serverDir,
  );
}

/// F2.17 + gate PR-5: ciclo remoto de eventos com `eventId`/`sequence`
/// monotonicos compartilhados entre fila e progresso.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? socketLogsDir;

  setUpAll(() async {
    registerFallbackValue(_e2eSchedule);
    registerFallbackValue(
      BackupDestination(
        id: 'dest-e2e',
        name: 'Local',
        type: DestinationType.local,
        config: '{"path":"C:/backup"}',
      ),
    );
    registerFallbackValue(ExecutionOrigin.remoteCommand);
    registerFallbackValue(<BackupDestination>[]);

    socketLogsDir = await Directory.systemTemp.createTemp('re_e2e_logs_');
    if (di.getIt.isRegistered<SocketLoggerService>()) {
      await di.getIt.unregister<SocketLoggerService>();
    }
    final socketLogger = SocketLoggerService(logsDirectory: socketLogsDir!.path)
      ..isEnabled = false;
    await socketLogger.initialize();
    di.getIt.registerSingleton<SocketLoggerService>(socketLogger);
  });

  tearDownAll(() async {
    if (di.getIt.isRegistered<SocketLoggerService>()) {
      await di.getIt.unregister<SocketLoggerService>();
    }
    if (socketLogsDir != null && await socketLogsDir!.exists()) {
      await socketLogsDir!.delete(recursive: true);
    }
  });

  group('Remote execution event correlation (integration)', () {
    test(
      'queue events and backup progress share monotonic server sequence',
      () async {
        final sequencer = ExecutionEventSequencer();
        final sent = <Message>[];
        final bus = QueueEventBus(
          sequencer: sequencer,
          broadcast: (_, message) async {
            sent.add(message);
          },
        );

        await bus.publishQueued(
          clientId: 'c1',
          runId: 'run-1',
          scheduleId: 'sch-1',
          queuePosition: 1,
        );

        final progressNotifier = _MockProgressNotifier();
        void Function()? progressListener;
        when(() => progressNotifier.addListener(any())).thenAnswer((inv) {
          progressListener = inv.positionalArguments.first as void Function();
        });
        when(() => progressNotifier.removeListener(any())).thenReturn(null);
        when(() => progressNotifier.currentSnapshot).thenReturn(
          const BackupProgressSnapshot(
            step: 'Executando',
            message: '50%',
            progress: 0.5,
          ),
        );

        final registry = RemoteExecutionRegistry();
        final handler = ScheduleMessageHandler(
          scheduleRepository: _MockScheduleRepository(),
          licensePolicyService: _MockLicensePolicyService(),
          schedulerService: _MockSchedulerService(),
          updateSchedule: _MockUpdateSchedule(),
          executeBackup: _MockExecuteBackup(),
          progressNotifier: progressNotifier,
          executionRegistry: registry,
          eventSequencer: sequencer,
        );

        registry.register(
          runId: 'run-1',
          scheduleId: 'sch-1',
          clientId: 'c1',
          requestId: 7,
          sendToClient: (_, message) async {
            sent.add(message);
          },
        );

        expect(progressListener, isNotNull);
        await Future(() => progressListener!());
        await Future<void>.delayed(Duration.zero);

        final queueSeq = sent
            .where((m) => m.header.type == MessageType.backupQueued)
            .map((m) => readQueueEvent(m)!.sequence)
            .single;
        final progressMsg = sent.firstWhere(isBackupProgressMessage);
        final progressSeq = getSequenceFromBackupMessage(progressMsg)!;

        expect(queueSeq, 1);
        expect(progressSeq, greaterThan(queueSeq));
        expect(getEventIdFromBackupMessage(progressMsg), isNotEmpty);
        expect(
          Uuid.isValidUUID(
            fromString: getEventIdFromBackupMessage(progressMsg)!,
          ),
          isTrue,
        );

        handler.dispose();
      },
    );
  });

  group('Remote execution socket pipeline (PR-5 E2E)', () {
    test(
      'server pushes backup complete then client downloads artifact',
      () async {
        final serverDir = await Directory.systemTemp.createTemp('re_art_');
        addTearDown(() => serverDir.delete(recursive: true));

        const artifactName = 'remote-backup-artifact.bin';
        const artifactContent = 'remote backup artifact e2e';
        final artifactFile = File(p.join(serverDir.path, artifactName));
        await artifactFile.writeAsString(artifactContent);
        final artifactPath = p.normalize(artifactFile.path);

        final fileTransferHandler = FileTransferMessageHandler(
          allowedBasePath: serverDir.path,
          lockService: _MockFileTransferLockService(),
        );
        final server = TcpSocketServer(
          fileTransferHandler: fileTransferHandler,
        );
        final port = _e2ePort();
        await server.start(port: port);
        addTearDown(server.stop);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );

        final manager = ConnectionManager();
        addTearDown(manager.disconnect);
        await manager.connect(host: '127.0.0.1', port: port);

        final sessionResult = await manager.getServerSession();
        expect(sessionResult.isSuccess(), isTrue);
        final clientId = sessionResult.getOrNull()!.clientId;

        const runId = 'run-e2e-download';
        const scheduleId = 'sch-e2e-download';

        manager.attachRemoteBackupListener(
          runId: runId,
          onProgress: null,
        );
        final completionFuture = manager.waitForRemoteBackupCompletion(runId);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        await server.sendToClient(
          clientId,
          createBackupProgressMessage(
            requestId: 1,
            scheduleId: scheduleId,
            step: 'Executando',
            message: '50%',
            progress: 0.5,
            runId: runId,
            eventId: 'evt-e2e-progress',
            sequence: 1,
          ),
        );
        await server.sendToClient(
          clientId,
          createBackupCompleteMessage(
            requestId: 2,
            scheduleId: scheduleId,
            backupPath: artifactPath,
            runId: runId,
            eventId: 'evt-e2e-complete',
            sequence: 2,
          ),
        );

        final backupResult = await completionFuture;
        expect(backupResult.isSuccess(), isTrue);
        expect(backupResult.getOrNull(), artifactPath);

        final clientDir = await Directory.systemTemp.createTemp('re_cli_');
        addTearDown(() => clientDir.delete(recursive: true));
        final outputPath = p.join(clientDir.path, 'downloaded.bin');

        final downloadResult = await manager.requestFile(
          filePath: artifactPath,
          outputPath: outputPath,
        );
        expect(downloadResult.isSuccess(), isTrue);
        expect(await File(outputPath).readAsString(), artifactContent);
      },
    );

    test(
      'backupStep with eventId updates onProgress before backupProgress',
      () async {
        final conn = await _connectRemoteExecutionE2eSocket();
        addTearDown(() => conn.serverDir.delete(recursive: true));
        addTearDown(conn.server.stop);
        addTearDown(conn.manager.disconnect);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );

        const runId = 'run-e2e-step';
        const scheduleId = 'sch-e2e-step';
        final steps = <String>[];

        conn.manager.attachRemoteBackupListener(
          runId: runId,
          onProgress: (step, _, _) => steps.add(step),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        await conn.server.sendToClient(
          conn.clientId,
          createBackupStepMessage(
            requestId: 20,
            scheduleId: scheduleId,
            step: 'Compactando',
            message: 'zip',
            progress: 0.2,
            runId: runId,
            eventId: 'evt-step-only',
            sequence: 1,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(steps, contains('Compactando'));
      },
    );

    test(
      'duplicate backupProgress with same eventId invokes onProgress once',
      () async {
        final conn = await _connectRemoteExecutionE2eSocket();
        addTearDown(() => conn.serverDir.delete(recursive: true));
        addTearDown(conn.server.stop);
        addTearDown(conn.manager.disconnect);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );

        const runId = 'run-e2e-dedup';
        const scheduleId = 'sch-e2e-dedup';

        var progressCalls = 0;
        conn.manager.attachRemoteBackupListener(
          runId: runId,
          onProgress: (_, _, _) => progressCalls++,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final dupProgress = createBackupProgressMessage(
          requestId: 10,
          scheduleId: scheduleId,
          step: 'Executando',
          message: '10%',
          progress: 0.1,
          runId: runId,
          eventId: 'evt-dedup-same',
          sequence: 1,
        );

        await conn.server.sendToClient(conn.clientId, dupProgress);
        await conn.server.sendToClient(conn.clientId, dupProgress);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(progressCalls, 1);
      },
    );
  });

  group('Remote execution startBackup E2E (PR-5)', () {
    test(
      'executeRemoteBackup via startBackup then downloads artifact',
      () async {
        const artifactContent = 'e2e via startRemoteBackup';
        final env = await _startStartBackupE2eServer(
          artifactContent: artifactContent,
        );
        addTearDown(() => env.serverDir.delete(recursive: true));
        addTearDown(env.server.stop);
        addTearDown(env.scheduleHandler.dispose);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );

        final clientDir = await Directory.systemTemp.createTemp('re_cli_sb_');
        addTearDown(() async {
          if (await clientDir.exists()) {
            await clientDir.delete(recursive: true);
          }
        });

        final manager = ConnectionManager();
        await manager.connect(host: '127.0.0.1', port: env.port);
        addTearDown(() async {
          await manager.disconnect();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });

        var progressEvents = 0;
        final backupResult = await manager.executeRemoteBackup(
          scheduleId: env.scheduleId,
          idempotencyKey: 'idem-e2e-start-backup',
          queueIfBusy: false,
          onProgress: (_, _, _) => progressEvents++,
        );

        expect(backupResult.isSuccess(), isTrue);
        expect(backupResult.getOrNull(), env.artifactPath);
        expect(progressEvents, greaterThan(0));

        final outputPath = p.join(clientDir.path, 'downloaded.bin');

        final downloadResult = await manager.requestFile(
          filePath: env.artifactPath,
          outputPath: outputPath,
        );
        expect(downloadResult.isSuccess(), isTrue);
        expect(await File(outputPath).readAsString(), artifactContent);
      },
    );

    test(
      'startRemoteBackup returns 202 runId before backup completes',
      () async {
        final blockBackup = Completer<rd.Result<bool>>();
        final serverDir = await Directory.systemTemp.createTemp('re_exec_blk_');
        addTearDown(() => serverDir.delete(recursive: true));

        final scheduleRepository = _MockScheduleRepository();
        when(
          () => scheduleRepository.getById(_e2eScheduleId),
        ).thenAnswer((_) async => rd.Success(_e2eSchedule));

        final licensePolicyService = _MockLicensePolicyService();
        when(
          () =>
              licensePolicyService.validateExecutionCapabilities(any(), any()),
        ).thenAnswer((_) async => const rd.Success(true));

        final schedulerService = _MockSchedulerService();
        when(() => schedulerService.isExecutingBackup).thenReturn(false);

        final executeBackup = _MockExecuteBackup();
        final progressNotifier = BackupProgressProvider();
        final registry = RemoteExecutionRegistry();
        final sequencer = ExecutionEventSequencer();

        when(
          () => executeBackup(
            _e2eScheduleId,
            executionOrigin: ExecutionOrigin.remoteCommand,
          ),
        ).thenAnswer((_) => blockBackup.future);

        final scheduleHandler = ScheduleMessageHandler(
          scheduleRepository: scheduleRepository,
          licensePolicyService: licensePolicyService,
          schedulerService: schedulerService,
          updateSchedule: _MockUpdateSchedule(),
          executeBackup: executeBackup,
          progressNotifier: progressNotifier,
          executionRegistry: registry,
          eventSequencer: sequencer,
        );

        final executionHandler = ExecutionMessageHandler(
          scheduleRepository: scheduleRepository,
          licensePolicyService: licensePolicyService,
          schedulerService: schedulerService,
          executeBackup: executeBackup,
          progressNotifier: progressNotifier,
          executionRegistry: registry,
          eventSequencer: sequencer,
          stagingUsageBytesProvider: () async => 0,
        );

        final server = TcpSocketServer(
          scheduleHandler: scheduleHandler,
          executionHandler: executionHandler,
          fileTransferHandler: FileTransferMessageHandler(
            allowedBasePath: serverDir.path,
            lockService: _MockFileTransferLockService(),
          ),
        );
        executionHandler.eventBus = QueueEventBus(
          broadcast: server.sendToClient,
          sequencer: sequencer,
        );

        final port = _e2ePort();
        await server.start(port: port);
        addTearDown(server.stop);
        addTearDown(scheduleHandler.dispose);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );

        final manager = ConnectionManager();
        addTearDown(manager.disconnect);
        await manager.connect(host: '127.0.0.1', port: port);

        final startResult = await manager.startRemoteBackup(
          scheduleId: _e2eScheduleId,
          idempotencyKey: 'idem-e2e-immediate',
        );
        expect(startResult.isSuccess(), isTrue);
        expect(registry.activeCount, 1);
        final start = startResult.getOrNull()!;
        expect(start.runId, isNotEmpty);
        expect(start.runId, startsWith('${_e2eScheduleId}_'));
        expect(start.isRunning, isTrue);

        blockBackup.complete(const rd.Success(true));
        progressNotifier.completeBackup(backupPath: r'C:\noop');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
    );

    test(
      'startRemoteBackup with queueIfBusy enqueues when scheduler is busy',
      () async {
        final env = await _startStartBackupE2eServer(
          artifactContent: 'unused',
          schedulerBusy: true,
        );
        addTearDown(() => env.serverDir.delete(recursive: true));
        addTearDown(env.server.stop);
        addTearDown(env.scheduleHandler.dispose);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );

        final manager = ConnectionManager();
        addTearDown(manager.disconnect);
        await manager.connect(host: '127.0.0.1', port: env.port);

        final startResult = await manager.startRemoteBackup(
          scheduleId: env.scheduleId,
          idempotencyKey: 'idem-e2e-queue',
          queueIfBusy: true,
        );

        expect(startResult.isSuccess(), isTrue);
        final start = startResult.getOrNull()!;
        expect(start.isQueued, isTrue);
        expect(start.queuePosition, 1);
        expect(start.runId, isNotEmpty);

        final metricsResult = await manager.getServerMetrics();
        expect(metricsResult.isSuccess(), isTrue);
        expect(metricsResult.getOrNull()!['queueDepth'], 1);
      },
    );

    test(
      'getServerMetrics includes socket telemetry after startBackup',
      () async {
        const artifactContent = 'e2e metrics observability';
        final env = await _startStartBackupE2eServer(
          artifactContent: artifactContent,
        );
        addTearDown(() => env.serverDir.delete(recursive: true));
        addTearDown(env.server.stop);
        addTearDown(env.scheduleHandler.dispose);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );

        final manager = ConnectionManager();
        addTearDown(manager.disconnect);
        await manager.connect(host: '127.0.0.1', port: env.port);

        final backupResult = await manager.executeRemoteBackup(
          scheduleId: env.scheduleId,
          idempotencyKey: 'idem-e2e-metrics',
          queueIfBusy: false,
        );
        expect(backupResult.isSuccess(), isTrue);

        final metricsResult = await manager.getServerMetrics();
        expect(metricsResult.isSuccess(), isTrue);
        final observability =
            metricsResult.getOrNull()!['observability']
                as Map<String, dynamic>? ??
            {};
        final durationKey = SocketTelemetryMetrics.requestDurationMs(
          MessageType.startBackupRequest.name,
        );
        expect(observability['${durationKey}_count'], greaterThan(0));
        expect(
          observability['socketRecentMutableAudits'],
          isA<List<dynamic>>(),
        );
      },
    );

    test(
      'executeRemoteBackup drains queue after active backup completes',
      () async {
        const artifactContent = 'e2e queue drain artifact';
        final env = await _startQueueDrainE2eServer(
          artifactContent: artifactContent,
        );
        addTearDown(() => env.serverDir.delete(recursive: true));
        addTearDown(env.server.stop);
        addTearDown(env.scheduleHandler.dispose);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );

        final manager = ConnectionManager();
        addTearDown(manager.disconnect);
        await manager.connect(host: '127.0.0.1', port: env.port);

        final firstStart = await manager.startRemoteBackup(
          scheduleId: _e2eScheduleId,
          idempotencyKey: 'idem-e2e-active',
        );
        expect(firstStart.isSuccess(), isTrue);
        expect(firstStart.getOrNull()!.isRunning, isTrue);

        final queuedStart = await manager.startRemoteBackup(
          scheduleId: _e2eScheduleId,
          idempotencyKey: 'idem-e2e-queued-drain',
          queueIfBusy: true,
        );
        expect(queuedStart.isSuccess(), isTrue);
        final queuedRunId = queuedStart.getOrNull()!.runId;
        expect(queuedStart.getOrNull()!.isQueued, isTrue);

        manager.attachRemoteBackupListener(
          runId: queuedRunId,
          onProgress: null,
        );
        final queuedCompletion = manager.waitForRemoteBackupCompletion(
          queuedRunId,
        );

        await Future<void>.delayed(const Duration(milliseconds: 80));
        env.blockFirstBackup.complete(const rd.Success(true));

        final queuedResult = await queuedCompletion;
        expect(queuedResult.isSuccess(), isTrue);
        expect(queuedResult.getOrNull(), env.artifactPath);
        expect(env.executeCallCount(), 2);
      },
    );

    test(
      'executeRemoteBackup with queueIfBusy uses public API through queue drain',
      () async {
        const artifactContent = 'e2e executeRemoteBackup queue drain';
        final env = await _startQueueDrainE2eServer(
          artifactContent: artifactContent,
        );
        addTearDown(() => env.serverDir.delete(recursive: true));
        addTearDown(env.server.stop);
        addTearDown(env.scheduleHandler.dispose);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );

        final manager = ConnectionManager();
        addTearDown(manager.disconnect);
        await manager.connect(host: '127.0.0.1', port: env.port);

        final firstStart = await manager.startRemoteBackup(
          scheduleId: _e2eScheduleId,
          idempotencyKey: 'idem-e2e-active-exec',
        );
        expect(firstStart.isSuccess(), isTrue);

        final queuedBackupFuture = manager.executeRemoteBackup(
          scheduleId: _e2eScheduleId,
          idempotencyKey: 'idem-e2e-exec-queue',
        );

        await Future<void>.delayed(const Duration(milliseconds: 80));
        env.blockFirstBackup.complete(const rd.Success(true));

        final queuedResult = await queuedBackupFuture;
        expect(queuedResult.isSuccess(), isTrue);
        expect(queuedResult.getOrNull(), env.artifactPath);
        expect(env.executeCallCount(), 2);
      },
    );

    test(
      'M6.2: deep queue enqueues 19 then drains 20 backups in FIFO order',
      () async {
        const depth = 20;
        const prefix = 'sch-deep-';
        final env = await _startDeepQueueE2eServer(
          artifactContent: 'deep queue fifo artifact',
        );
        addTearDown(() => env.serverDir.delete(recursive: true));
        addTearDown(env.server.stop);
        addTearDown(env.scheduleHandler.dispose);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );

        final manager = ConnectionManager();
        addTearDown(manager.disconnect);
        await manager.connect(host: '127.0.0.1', port: env.port);

        env.setSchedulerBusy(false);
        const firstId = '${prefix}0';
        final firstStart = await manager.startRemoteBackup(
          scheduleId: firstId,
          idempotencyKey: 'idem-deep-0',
        );
        expect(firstStart.isSuccess(), isTrue);
        expect(firstStart.getOrNull()!.isRunning, isTrue);

        env.setSchedulerBusy(true);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        for (var i = 1; i < depth; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final scheduleId = '$prefix$i';
          final queued = await manager.startRemoteBackup(
            scheduleId: scheduleId,
            idempotencyKey: 'idem-deep-$i',
            queueIfBusy: true,
          );
          expect(queued.isSuccess(), isTrue, reason: scheduleId);
          expect(queued.getOrNull()!.isQueued, isTrue);
          expect(queued.getOrNull()!.queuePosition, i);
        }

        final queueSnapshot = await manager.getExecutionQueue();
        expect(queueSnapshot.isSuccess(), isTrue);
        expect(queueSnapshot.getOrNull()!.queue.length, depth - 1);

        final metricsBusy = await manager.getServerMetrics();
        expect(metricsBusy.getOrNull()!['queueDepth'], depth - 1);

        env.setSchedulerBusy(false);
        env.releaseFirstBackup.complete(const rd.Success(true));

        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (env.executionOrder.length < depth &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        expect(
          env.executionOrder,
          [for (var i = 0; i < depth; i++) '$prefix$i'],
        );
        expect(env.executionHandler.queueService.isEmpty, isTrue);

        final metricsIdle = await manager.getServerMetrics();
        expect(metricsIdle.getOrNull()!['queueDepth'], 0);
      },
    );
  });

  group('Remote execution chaos E2E (M6.3 PR-5)', () {
    test(
      'requestFile while disconnected fails then reconnect downloads artifact',
      () async {
        const artifactBytes = 256 * 1024;
        final largeContent = 'x' * artifactBytes;
        final env = await _startStartBackupE2eServer(
          artifactContent: largeContent,
        );
        addTearDown(() => env.serverDir.delete(recursive: true));
        addTearDown(env.server.stop);
        addTearDown(env.scheduleHandler.dispose);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );

        final clientDir = await Directory.systemTemp.createTemp('re_chaos_dl_');
        addTearDown(() async {
          if (await clientDir.exists()) {
            await clientDir.delete(recursive: true);
          }
        });

        final manager = ConnectionManager();
        await manager.connect(host: '127.0.0.1', port: env.port);
        await manager.disconnect();

        final outputPath = p.join(clientDir.path, 'large.bin');
        final offline = await manager.requestFile(
          filePath: env.artifactPath,
          outputPath: outputPath,
        );
        expect(offline.isError(), isTrue);

        await manager.connect(host: '127.0.0.1', port: env.port);
        addTearDown(() async {
          await manager.disconnect();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });

        final retry = await manager.requestFile(
          filePath: env.artifactPath,
          outputPath: outputPath,
        );
        expect(retry.isSuccess(), isTrue);
        final downloadedLen = await File(outputPath).length();
        expect(downloadedLen, artifactBytes);
      },
    );

    test(
      'getExecutionStatus after client disconnect while backup is blocked',
      () async {
        final blockBackup = Completer<rd.Result<bool>>();
        final env = await _startQueueDrainE2eServer(
          artifactContent: 'chaos status probe',
        );
        addTearDown(() => env.serverDir.delete(recursive: true));
        addTearDown(env.server.stop);
        addTearDown(env.scheduleHandler.dispose);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );

        final manager1 = ConnectionManager();
        await manager1.connect(host: '127.0.0.1', port: env.port);

        final start = await manager1.startRemoteBackup(
          scheduleId: _e2eScheduleId,
          idempotencyKey: 'idem-chaos-status',
        );
        expect(start.isSuccess(), isTrue);
        final runId = start.getOrNull()!.runId;
        expect(start.getOrNull()!.state, ExecutionState.running);

        manager1.attachRemoteBackupListener(runId: runId, onProgress: null);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await manager1.disconnect();

        final manager2 = ConnectionManager();
        await manager2.connect(host: '127.0.0.1', port: env.port);
        addTearDown(manager2.disconnect);

        final status = await manager2.getExecutionStatus(runId);
        expect(status.isSuccess(), isTrue);
        expect(status.getOrNull()!.state, ExecutionState.running);
        expect(status.getOrNull()!.runId, runId);

        blockBackup.complete(const rd.Success(true));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      },
    );

    test(
      'M8.4: RemoteSchedulesProvider resumes after reconnect during blocked backup',
      () async {
        final env = await _startQueueDrainE2eServer(
          artifactContent: 'm8.4 provider resume',
        );
        addTearDown(() => env.serverDir.delete(recursive: true));
        addTearDown(env.server.stop);
        addTearDown(env.scheduleHandler.dispose);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );

        final manager = ConnectionManager();
        await manager.connect(host: '127.0.0.1', port: env.port);

        final provider = RemoteSchedulesProvider(
          manager,
          tempDirectoryService: StubTempDirectoryService(),
        );

        final executionFuture = provider.executeSchedule(_e2eScheduleId);

        final runIdDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (provider.activeRunId == null &&
            DateTime.now().isBefore(runIdDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(provider.activeRunId, isNotNull);

        await manager.disconnect();
        provider.clearExecutionStateOnDisconnect();

        final executionAfterDisconnect = await executionFuture;
        expect(executionAfterDisconnect, isFalse);
        expect(provider.activeRunId, isNotNull);
        expect(provider.executingScheduleId, _e2eScheduleId);
        expect(provider.error, contains('reconectar'));

        await manager.connect(host: '127.0.0.1', port: env.port);
        addTearDown(manager.disconnect);

        final runId = provider.activeRunId!;
        final statusWhileBlocked = await manager.getExecutionStatus(runId);
        expect(statusWhileBlocked.isSuccess(), isTrue);
        expect(statusWhileBlocked.getOrNull()!.state, ExecutionState.running);

        final resumeFuture = provider.tryResumeExecutionAfterReconnect();

        final resumeStartedDeadline = DateTime.now().add(
          const Duration(seconds: 5),
        );
        while (DateTime.now().isBefore(resumeStartedDeadline)) {
          if (provider.backupMessage?.contains('andamento') ?? false) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(provider.error, isNull);
        expect(provider.backupMessage, contains('andamento'));

        env.blockFirstBackup.complete(const rd.Success(true));

        await resumeFuture.timeout(const Duration(seconds: 20));
        expect(provider.error, isNull);
        expect(provider.isExecuting, isFalse);

        await manager.disconnect();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
    );
  });

  group('Remote execution local destination E2E (PR-5)', () {
    test(
      'executeSchedule downloads artifact and uploads to linked local destination',
      () async {
        const artifactContent = 'e2e remote to local destination';
        const destId = 'dest-e2e-local';
        final env = await _startStartBackupE2eServer(
          artifactContent: artifactContent,
        );
        addTearDown(() => env.serverDir.delete(recursive: true));
        addTearDown(env.server.stop);
        addTearDown(env.scheduleHandler.dispose);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );

        final connectionManager = ConnectionManager();
        addTearDown(connectionManager.disconnect);
        await connectionManager.connect(host: '127.0.0.1', port: env.port);

        final machineSettings = _MockMachineSettingsRepository();
        when(
          machineSettings.getScheduleTransferDestinationsJson,
        ).thenAnswer(
          (_) async => jsonEncode(<String, dynamic>{
            env.scheduleId: <String>[destId],
          }),
        );

        final destinationRepository = _MockBackupDestinationRepository();
        final destination = BackupDestination(
          id: destId,
          name: 'Destino local E2E',
          type: DestinationType.local,
          config: r'{"path":"C:\\backup\\e2e"}',
        );
        when(() => destinationRepository.getById(destId)).thenAnswer(
          (_) async => rd.Success(destination),
        );

        final sendFileService = _MockSendFileToDestinationService();
        when(
          () => sendFileService.sendFile(
            localFilePath: any(named: 'localFilePath'),
            destination: any(named: 'destination'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async => const rd.Success(()));

        final tempDirectory = StubTempDirectoryService(
          machineSettings: machineSettings,
        );
        final transferProvider = RemoteFileTransferProvider(
          connectionManager,
          destinationRepository,
          sendFileService,
          tempDirectory,
          machineSettings,
        );

        final schedulesProvider = RemoteSchedulesProvider(
          connectionManager,
          transferProvider: transferProvider,
          tempDirectoryService: tempDirectory,
        );

        final ok = await schedulesProvider.executeSchedule(env.scheduleId);

        expect(ok, isTrue);
        expect(schedulesProvider.error, isNull);
        verify(
          () => sendFileService.sendFile(
            localFilePath: any(named: 'localFilePath'),
            destination: destination,
            onProgress: any(named: 'onProgress'),
          ),
        ).called(1);

        final downloaded = await tempDirectory.getDownloadsDirectory();
        final expectedFile = File(
          p.join(
            downloaded.path,
            p.basename(env.artifactPath),
          ),
        );
        expect(await expectedFile.exists(), isFalse);
      },
    );
  });
}
