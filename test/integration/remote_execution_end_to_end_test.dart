import 'dart:io';

import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/domain/constants/transfer_lease.dart';
import 'package:backup_database/domain/entities/backup_progress_snapshot.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_file_transfer_lock_service.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/domain/use_cases/scheduling/update_schedule.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/queue_events.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/server/execution_event_sequencer.dart';
import 'package:backup_database/infrastructure/socket/server/file_transfer_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/queue_event_bus.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class _MockFileTransferLockService implements IFileTransferLockService {
  @override
  Future<bool> tryAcquireLock(
    String filePath, {
    String owner = 'unknown',
    String? runId,
    Duration leaseTtl = kDefaultTransferLeaseTtl,
  }) async =>
      true;

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
    throw StateError('getServerSession failed: ${sessionResult.exceptionOrNull()}');
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
        expect(Uuid.isValidUUID(fromString: getEventIdFromBackupMessage(progressMsg)!), isTrue);

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
}
