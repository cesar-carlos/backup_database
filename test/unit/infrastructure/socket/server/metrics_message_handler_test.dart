import 'dart:io';

import 'package:backup_database/application/services/metrics_collector.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_running_state.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/metrics_messages.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_service.dart';
import 'package:backup_database/infrastructure/socket/server/metrics_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:backup_database/infrastructure/socket/server/remote_staging_artifact_ttl.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_telemetry.dart';
import 'package:backup_database/infrastructure/socket/server/socket_telemetry_constants.dart';
import 'package:backup_database/infrastructure/utils/staging_usage_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class _MockBackupHistoryRepository extends Mock
    implements IBackupHistoryRepository {}

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

class _MockBackupRunningState extends Mock implements IBackupRunningState {}

void main() {
  late _MockBackupHistoryRepository historyRepo;
  late _MockScheduleRepository scheduleRepo;
  late _MockBackupRunningState runningState;
  late RemoteExecutionRegistry registry;

  setUp(() {
    historyRepo = _MockBackupHistoryRepository();
    scheduleRepo = _MockScheduleRepository();
    runningState = _MockBackupRunningState();
    registry = RemoteExecutionRegistry();

    when(
      () => historyRepo.getAll(limit: any(named: 'limit')),
    ).thenAnswer((_) async => const rd.Success(<BackupHistory>[]));
    when(
      () => historyRepo.getByDateRange(any(), any()),
    ).thenAnswer((_) async => const rd.Success(<BackupHistory>[]));
    when(
      () => scheduleRepo.getEnabled(),
    ).thenAnswer((_) async => const rd.Success(<Schedule>[]));
    when(() => runningState.isRunning).thenReturn(false);
    when(() => runningState.currentBackupName).thenReturn(null);
  });

  Future<Map<String, dynamic>> captureMetricsPayload(
    MetricsMessageHandler handler,
  ) async {
    Message? sent;
    Future<void> capture(String clientId, Message msg) async {
      sent = msg;
    }

    await handler.handle(
      'client-1',
      createMetricsRequestMessage(),
      capture,
    );

    expect(sent, isNotNull);
    expect(sent!.header.type, MessageType.metricsResponse);
    return sent!.payload;
  }

  group('MetricsMessageHandler enriquecido (M5.3 / M7.1)', () {
    test('publica serverTimeUtc em todos os payloads', () async {
      final fixedClock = DateTime.utc(2026, 4, 19, 15, 30);
      final handler = MetricsMessageHandler(
        backupHistoryRepository: historyRepo,
        scheduleRepository: scheduleRepo,
        backupRunningState: runningState,
        clock: () => fixedClock,
      );

      final payload = await captureMetricsPayload(handler);
      expect(payload['serverTimeUtc'], '2026-04-19T15:30:00.000Z');
    });

    test(
      'sem RemoteExecutionRegistry: nao publica activeRunId nem activeRunCount',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload.containsKey('activeRunId'), isFalse);
        expect(payload.containsKey('activeRunCount'), isFalse);
      },
    );

    test(
      'com registry vazio: publica activeRunCount=0 e omite activeRunId',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          executionRegistry: registry,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload['activeRunCount'], 0);
        expect(payload.containsKey('activeRunId'), isFalse);
      },
    );

    test(
      'com ExecutionQueueService: publica queueDepth e maxQueueSize',
      () async {
        final queue = ExecutionQueueService(maxQueueSize: 25);
        await queue.tryEnqueue(
          scheduleId: 'sch-q',
          clientId: 'client-1',
          requestId: 1,
          requestedBy: 'manual',
        );

        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          queueService: queue,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload['queueDepth'], 1);
        expect(payload['maxQueueSize'], 25);
      },
    );

    test(
      'sem ExecutionQueueService: nao publica queueDepth',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload.containsKey('queueDepth'), isFalse);
        expect(payload.containsKey('maxQueueSize'), isFalse);
      },
    );

    test(
      'com run ativo e staging: publica artifactExpiresAt',
      () async {
        final stagingBase = await Directory.systemTemp.createTemp(
          'metrics_ttl_',
        );
        addTearDown(() => stagingBase.delete(recursive: true));
        final runId = registry.generateRunId('schedule-X');
        final artifactDir = Directory(
          p.join(stagingBase.path, 'remote', runId),
        );
        await artifactDir.create(recursive: true);
        final artifact = File(p.join(artifactDir.path, 'a.bak'));
        final mtime = DateTime.utc(2026, 5, 1, 8);
        await artifact.writeAsString('data');
        await artifact.setLastModified(mtime);

        registry.register(
          runId: runId,
          scheduleId: 'schedule-X',
          clientId: 'client-A',
          requestId: 1,
          sendToClient: (clientId, msg) async {},
        );

        final ttl = RemoteStagingArtifactTtl();
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          executionRegistry: registry,
          artifactExpiresAtForRunId: (id) =>
              ttl.expiresAtForRunInStaging(stagingBase.path, id),
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload['artifactExpiresAt'], '2026-05-02T08:00:00.000Z');
      },
    );

    test(
      'com 1 execucao ativa: publica activeRunId + activeRunCount=1',
      () async {
        registry.register(
          runId: registry.generateRunId('schedule-X'),
          scheduleId: 'schedule-X',
          clientId: 'client-A',
          requestId: 1,
          sendToClient: (clientId, msg) async {},
        );

        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          executionRegistry: registry,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload['activeRunCount'], 1);
        expect(payload['activeRunId'], startsWith('schedule-X_'));
      },
    );

    test(
      'sem stagingUsageBytesProvider: nao publica o campo',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload.containsKey('stagingUsageBytes'), isFalse);
      },
    );

    test(
      'com stagingUsageBytesProvider: publica valor retornado',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          stagingUsageBytesProvider: () async => 1234567,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload['stagingUsageBytes'], 1234567);
        expect(
          payload['stagingUsageWarnThresholdBytes'],
          StagingUsagePolicy.warnThresholdBytes,
        );
        expect(
          payload['stagingUsageBlockThresholdBytes'],
          StagingUsagePolicy.blockThresholdBytes,
        );
        expect(payload['stagingUsageLevel'], 'ok');
      },
    );

    test(
      'stagingUsageLevel reflecte warn acima de 5 GiB',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          stagingUsageBytesProvider: () async =>
              StagingUsagePolicy.warnThresholdBytes + 1,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload['stagingUsageLevel'], 'warn');
      },
    );

    test(
      'com provider que retorna 0 (diretorio vazio): publica 0 explicitamente',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          stagingUsageBytesProvider: () async => 0,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload['stagingUsageBytes'], 0);
      },
    );

    test(
      'mescla socket telemetry em payload.observability',
      () async {
        final metrics = MetricsCollector();
        final telemetry = SocketServerTelemetry(metricsCollector: metrics);
        const clientId = 'metrics-client';
        const requestId = 42;

        final startRequest = createStartBackupRequest(
          scheduleId: 'sch-metrics',
          idempotencyKey: 'idem-metrics',
          requestId: requestId,
        );
        telemetry.onRequestReceived(clientId, startRequest);
        telemetry.onResponseSent(
          clientId,
          createStartBackupResponse(
            requestId: requestId,
            runId: 'sch-metrics_test',
            state: ExecutionState.running,
            scheduleId: 'sch-metrics',
            serverTimeUtc: DateTime.utc(2026, 4, 19),
          ),
        );

        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          metricsCollector: metrics,
          socketTelemetry: telemetry,
        );

        final payload = await captureMetricsPayload(handler);
        final observability =
            payload['observability'] as Map<String, dynamic>? ?? {};
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
      'falha ao montar payload -> protocol error (nao schedule error)',
      () async {
        when(
          () => historyRepo.getAll(limit: any(named: 'limit')),
        ).thenThrow(Exception('db down'));

        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
        );

        Message? sent;
        Future<void> capture(String clientId, Message msg) async {
          sent = msg;
        }

        await handler.handle(
          'client-1',
          createMetricsRequestMessage(),
          capture,
        );

        expect(sent, isNotNull);
        expect(sent!.header.type, MessageType.error);
        expect(getErrorCodeFromMessage(sent!), ErrorCode.unknown);
        expect(getErrorFromMessage(sent!), contains('db down'));
      },
    );

    test(
      'campos legados continuam presentes apos enriquecimento (zero regressao)',
      () async {
        when(() => runningState.isRunning).thenReturn(true);
        when(() => runningState.currentBackupName).thenReturn('Backup Diario');

        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
        );

        final payload = await captureMetricsPayload(handler);
        // Campos pre-existentes
        expect(payload['totalBackups'], 0);
        expect(payload['backupsToday'], 0);
        expect(payload['failedToday'], 0);
        expect(payload['activeSchedules'], 0);
        expect(payload['recentBackups'], isA<List<dynamic>>());
        expect(payload['backupInProgress'], isTrue);
        expect(payload['backupScheduleName'], 'Backup Diario');
        // Campo novo (sempre publicado)
        expect(payload.containsKey('serverTimeUtc'), isTrue);
      },
    );
  });
}
