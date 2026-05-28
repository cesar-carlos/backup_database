import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/protocol/diagnostics_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../helpers/fake_remote_schedules_connection_manager.dart';
import '../../../helpers/stub_temp_directory_service.dart';

void main() {
  setUpAll(() {
    if (!di.getIt.isRegistered<SocketLoggerService>()) {
      di.getIt.registerSingleton<SocketLoggerService>(
        SocketLoggerService(logsDirectory: Directory.systemTemp.path),
      );
    }
  });

  late FakeRemoteSchedulesConnectionManager connectionManager;
  late StubTempDirectoryService tempDirectory;
  late RemoteSchedulesProvider provider;

  const scheduleId = 'sch-remote-1';

  Schedule sampleSchedule({String id = scheduleId, bool enabled = true}) =>
      Schedule(
        id: id,
        name: 'Backup remoto',
        databaseConfigId: 'db-1',
        databaseType: DatabaseType.sqlServer,
        scheduleType: ScheduleType.daily.name,
        scheduleConfig: '{"hour":2,"minute":0}',
        destinationIds: const ['dest-1'],
        backupFolder: r'C:\backup',
        enabled: enabled,
      );

  setUp(() {
    connectionManager = FakeRemoteSchedulesConnectionManager();
    tempDirectory = StubTempDirectoryService();
    provider = RemoteSchedulesProvider(
      connectionManager,
      tempDirectoryService: tempDirectory,
    );
  });

  group('RemoteSchedulesProvider.executeSchedule', () {
    test('should return false when not connected', () async {
      connectionManager.simulateConnected = false;

      final ok = await provider.executeSchedule(scheduleId);

      expect(ok, isFalse);
      expect(provider.error, contains('Conecte-se'));
      expect(connectionManager.executeRemoteBackupCallCount, 0);
    });

    test('should call executeRemoteBackup when runId is supported', () async {
      connectionManager.remoteBackupResult = const rd.Success('');

      final ok = await provider.executeSchedule(scheduleId);

      expect(ok, isTrue);
      expect(connectionManager.executeRemoteBackupCallCount, 1);
      expect(connectionManager.executeScheduleCallCount, 0);
      expect(connectionManager.validatePreflightCallCount, 1);
      expect(connectionManager.lastScheduleId, scheduleId);
      expect(connectionManager.notifiedRunId, '${scheduleId}_run-test');
    });

    test('should call legacy executeSchedule when runId unsupported', () async {
      connectionManager.simulateRunIdSupported = false;
      connectionManager.remoteBackupResult = const rd.Success('');

      await provider.executeSchedule(scheduleId);

      expect(connectionManager.executeScheduleCallCount, 1);
      expect(connectionManager.executeRemoteBackupCallCount, 0);
      expect(connectionManager.validatePreflightCallCount, 0);
    });

    test('should not start backup when preflight has warnings only', () async {
      connectionManager.preflightResult = rd.Success(
        PreflightResult(
          status: PreflightStatus.passedWithWarnings,
          checks: const [
            PreflightCheckResult(
              name: 'disk_space',
              passed: false,
              severity: PreflightSeverity.warning,
              message: 'Pouco espaço livre',
            ),
          ],
          serverTimeUtc: DateTime.utc(2026),
        ),
      );

      final ok = await provider.executeSchedule(scheduleId);

      expect(ok, isFalse);
      expect(provider.isExecuting, isFalse);
      expect(provider.error, isNull);
      expect(connectionManager.executeRemoteBackupCallCount, 0);
    });

    test('should block when preflight is blocked', () async {
      connectionManager.preflightResult = rd.Success(
        PreflightResult(
          status: PreflightStatus.blocked,
          checks: const [
            PreflightCheckResult(
              name: 'temp_dir_writable',
              passed: false,
              severity: PreflightSeverity.blocking,
              message: 'Sem permissão no staging',
            ),
          ],
          serverTimeUtc: DateTime.utc(2026),
        ),
      );

      final ok = await provider.executeSchedule(scheduleId);

      expect(ok, isFalse);
      expect(provider.error, contains('Sem permissão'));
      expect(connectionManager.executeRemoteBackupCallCount, 0);
    });

    test('should reset state when remote backup fails', () async {
      connectionManager.remoteBackupResult = rd.Failure(
        Exception('backup falhou'),
      );

      final ok = await provider.executeSchedule(scheduleId);

      expect(ok, isFalse);
      expect(provider.isExecuting, isFalse);
      expect(provider.error, isNotNull);
    });
  });

  group('RemoteSchedulesProvider.runPreflightForSchedule', () {
    test('should return notApplicable when runId unsupported', () async {
      connectionManager.simulateRunIdSupported = false;

      final result = await provider.runPreflightForSchedule();

      expect(result.action, RemotePreflightUiAction.notApplicable);
      expect(connectionManager.validatePreflightCallCount, 0);
    });

    test('should return proceed when preflight passed', () async {
      final result = await provider.runPreflightForSchedule();

      expect(result.action, RemotePreflightUiAction.proceed);
      expect(result.preflight?.status, PreflightStatus.passed);
      expect(connectionManager.validatePreflightCallCount, 1);
    });

    test('should return showDialog when preflight is blocked', () async {
      connectionManager.preflightResult = rd.Success(
        PreflightResult(
          status: PreflightStatus.blocked,
          checks: const [
            PreflightCheckResult(
              name: 'compression_tool',
              passed: false,
              severity: PreflightSeverity.blocking,
              message: 'Ferramenta ausente',
            ),
          ],
          serverTimeUtc: DateTime.utc(2026),
        ),
      );

      final result = await provider.runPreflightForSchedule();

      expect(result.action, RemotePreflightUiAction.showDialog);
      expect(result.isBlocked, isTrue);
      expect(result.hasWarningsOnly, isFalse);
    });

    test('should return showDialog when preflight has warnings only', () async {
      connectionManager.preflightResult = rd.Success(
        PreflightResult(
          status: PreflightStatus.passedWithWarnings,
          checks: const [
            PreflightCheckResult(
              name: 'disk_space',
              passed: false,
              severity: PreflightSeverity.warning,
              message: 'Pouco espaço',
            ),
          ],
          serverTimeUtc: DateTime.utc(2026),
        ),
      );

      final result = await provider.runPreflightForSchedule();

      expect(result.action, RemotePreflightUiAction.showDialog);
      expect(result.isBlocked, isFalse);
      expect(result.hasWarningsOnly, isTrue);
    });

    test('should proceed when preflight request fails', () async {
      connectionManager.preflightResult = rd.Failure(Exception('timeout'));

      final result = await provider.runPreflightForSchedule();

      expect(result.action, RemotePreflightUiAction.proceed);
      expect(result.preflight, isNull);
    });
  });

  group('RemoteSchedulesProvider.disconnect and resume', () {
    test(
      'should preserve activeRunId when executeRemoteBackup fails on disconnect',
      () async {
        connectionManager.remoteBackupCompleter =
            Completer<rd.Result<String>>();
        final executionFuture = provider.executeSchedule(scheduleId);
        await Future<void>.delayed(Duration.zero);

        expect(provider.activeRunId, '${scheduleId}_run-test');

        connectionManager.remoteBackupCompleter!.complete(
          rd.Failure(Exception('Disconnected during backup')),
        );

        final ok = await executionFuture;

        expect(ok, isFalse);
        expect(provider.activeRunId, '${scheduleId}_run-test');
        expect(provider.executingScheduleId, scheduleId);
        expect(provider.error, contains('reconectar'));
      },
    );

    test('should preserve runId on disconnect for M8.4', () async {
      connectionManager.remoteBackupCompleter = Completer<rd.Result<String>>();
      unawaited(provider.executeSchedule(scheduleId));
      await Future<void>.delayed(Duration.zero);

      expect(connectionManager.notifiedRunId, '${scheduleId}_run-test');
      provider.clearExecutionStateOnDisconnect();

      expect(provider.executingScheduleId, scheduleId);
      expect(provider.isExecuting, isFalse);
      expect(provider.error, contains('reconectar'));

      connectionManager.remoteBackupCompleter!.complete(const rd.Success(''));
    });

    test('should no-op resume when not disconnected during run', () async {
      await provider.tryResumeExecutionAfterReconnect();
      expect(connectionManager.getExecutionStatusCallCount, 0);
    });

    test('should resume running backup after reconnect', () async {
      connectionManager.remoteBackupCompleter = Completer<rd.Result<String>>();
      unawaited(provider.executeSchedule(scheduleId));
      await Future<void>.delayed(Duration.zero);
      provider.clearExecutionStateOnDisconnect();

      connectionManager.executionStatusToReturn = ExecutionStatusResult(
        runId: '${scheduleId}_run-test',
        state: ExecutionState.running,
        serverTimeUtc: DateTime.utc(2026),
        scheduleId: scheduleId,
      );
      connectionManager.waitForCompletionResult = const rd.Success(
        'remote/sch_run-test/file.bak',
      );

      await provider.tryResumeExecutionAfterReconnect();

      expect(connectionManager.getExecutionStatusCallCount, 1);
      expect(connectionManager.attachListenerCallCount, 1);
      expect(connectionManager.waitForCompletionCallCount, 1);
      expect(provider.isExecuting, isFalse);

      connectionManager.remoteBackupCompleter!.complete(const rd.Success(''));
    });

    test(
      '§audit-2026-05-28 wave 2 P1: '
      'concurrent tryResumeExecutionAfterReconnect runs only once',
      () async {
        // Regressão: na wave 2 descobrimos que ServerConnectionProvider e
        // RemoteSchedulesPage chamavam o resume em paralelo quando o
        // usuário estava na página no momento da reconexão. O segundo
        // caller disparava `getExecutionStatus` de novo e duplicava
        // downloads do mesmo runId. Agora a página delegou ao
        // ServerConnectionProvider e o provider tem guard de
        // re-entrância — defesa em profundidade caso algum caller
        // futuro volte a chamar duas vezes.
        connectionManager.remoteBackupCompleter =
            Completer<rd.Result<String>>();
        unawaited(provider.executeSchedule(scheduleId));
        await Future<void>.delayed(Duration.zero);
        provider.clearExecutionStateOnDisconnect();

        connectionManager.executionStatusToReturn = ExecutionStatusResult(
          runId: '${scheduleId}_run-test',
          state: ExecutionState.running,
          serverTimeUtc: DateTime.utc(2026),
          scheduleId: scheduleId,
        );
        connectionManager.waitForCompletionResult = const rd.Success(
          'remote/sch_run-test/file.bak',
        );

        // Dispara dois resumes em paralelo
        final f1 = provider.tryResumeExecutionAfterReconnect();
        final f2 = provider.tryResumeExecutionAfterReconnect();
        await Future.wait([f1, f2]);

        // Só um deles efetivamente bateu no servidor
        expect(connectionManager.getExecutionStatusCallCount, 1);
        expect(connectionManager.attachListenerCallCount, 1);
        expect(connectionManager.waitForCompletionCallCount, 1);

        connectionManager.remoteBackupCompleter!.complete(const rd.Success(''));
      },
    );

    test(
      'should clear state when artifact expired on completed resume',
      () async {
        connectionManager.remoteBackupCompleter =
            Completer<rd.Result<String>>();
        unawaited(provider.executeSchedule(scheduleId));
        await Future<void>.delayed(Duration.zero);
        provider.clearExecutionStateOnDisconnect();

        connectionManager.simulateArtifactRetentionSupported = true;
        connectionManager.executionStatusToReturn = ExecutionStatusResult(
          runId: '${scheduleId}_run-test',
          state: ExecutionState.completed,
          serverTimeUtc: DateTime.utc(2026),
          scheduleId: scheduleId,
        );
        connectionManager.artifactMetadataResult = rd.Success(
          ArtifactMetadataResult(
            runId: '${scheduleId}_run-test',
            found: true,
            serverTimeUtc: DateTime.utc(2026),
            stagingPath: 'remote/expired.bak',
            expiresAt: DateTime.utc(2020),
          ),
        );

        await provider.tryResumeExecutionAfterReconnect();

        expect(provider.isExecuting, isFalse);
        expect(provider.activeRunId, isNull);
        expect(provider.error, contains('expirou'));

        connectionManager.remoteBackupCompleter!.complete(const rd.Success(''));
      },
    );
  });

  group('RemoteSchedulesProvider health gate', () {
    test('should block execute when server health gate fails', () async {
      var healthGateCalls = 0;
      provider = RemoteSchedulesProvider(
        connectionManager,
        tempDirectoryService: tempDirectory,
        ensureServerHealthy: () async {
          healthGateCalls++;
          return false;
        },
      );

      final ok = await provider.executeSchedule(scheduleId);

      expect(ok, isFalse);
      expect(healthGateCalls, 1);
      expect(provider.error, contains('saúde'));
      expect(connectionManager.executeRemoteBackupCallCount, 0);
    });
  });

  group('RemoteSchedulesProvider execution queue', () {
    test('should load execution queue snapshot when supported', () async {
      connectionManager.simulateQueueSupported = true;
      const runId = 'run-queue-1';
      connectionManager.executionQueueResult = rd.Success(
        ExecutionQueueResult(
          queue: [
            QueuedExecution(
              runId: runId,
              scheduleId: scheduleId,
              queuedAt: DateTime.utc(2026),
              queuedPosition: 1,
            ),
          ],
          totalQueued: 1,
          maxQueueSize: 50,
          serverTimeUtc: DateTime.utc(2026),
        ),
      );

      await provider.loadExecutionQueue();

      expect(connectionManager.getExecutionQueueCallCount, 1);
      expect(provider.executionQueue, hasLength(1));
      expect(provider.executionQueue.first.runId, runId);
      expect(provider.isLoadingExecutionQueue, isFalse);
    });

    test('should cancel queued backup by runId', () async {
      connectionManager.simulateQueueSupported = true;
      const runId = 'run-cancel-queue';

      final ok = await provider.cancelQueuedRemoteBackup(runId);

      expect(ok, isTrue);
      expect(connectionManager.cancelQueuedRemoteBackupCallCount, 1);
      expect(connectionManager.lastRunIdForCancelQueued, runId);
      expect(connectionManager.getExecutionQueueCallCount, 1);
    });
  });

  group('RemoteSchedulesProvider CRUD', () {
    test('should return false when create while disconnected', () async {
      connectionManager.simulateConnected = false;

      final ok = await provider.createRemoteSchedule(sampleSchedule());

      expect(ok, isFalse);
      expect(provider.error, contains('Conecte-se'));
      expect(connectionManager.createRemoteScheduleCallCount, 0);
    });

    test('should call createRemoteSchedule and reload schedules', () async {
      final created = sampleSchedule(id: 'sch-new');
      connectionManager.createRemoteScheduleResult = rd.Success(
        ScheduleMutationResult(
          operation: 'created',
          scheduleId: created.id,
          schedule: created,
        ),
      );
      connectionManager.listSchedulesResult = rd.Success([created]);

      final ok = await provider.createRemoteSchedule(
        sampleSchedule(id: 'draft'),
      );

      expect(ok, isTrue);
      expect(connectionManager.createRemoteScheduleCallCount, 1);
      expect(provider.schedules, hasLength(1));
      expect(provider.schedules.first.id, created.id);
    });

    test('should surface failureUserMessage when create fails', () async {
      connectionManager.createRemoteScheduleResult = rd.Failure(
        Exception('payload invalido'),
      );

      final ok = await provider.createRemoteSchedule(sampleSchedule());

      expect(ok, isFalse);
      expect(provider.error, contains('payload invalido'));
    });

    test('should call deleteRemoteSchedule and reload schedules', () async {
      final existing = sampleSchedule();
      connectionManager.listSchedulesResult = rd.Success([existing]);
      await provider.loadSchedules();

      connectionManager.listSchedulesResult = const rd.Success(<Schedule>[]);

      final ok = await provider.deleteRemoteSchedule(existing.id);

      expect(ok, isTrue);
      expect(connectionManager.deleteRemoteScheduleCallCount, 1);
      expect(connectionManager.lastMutationScheduleId, existing.id);
      expect(provider.schedules, isEmpty);
    });

    test('should call pauseRemoteSchedule when pausing', () async {
      final existing = sampleSchedule();
      connectionManager.listSchedulesResult = rd.Success([existing]);
      await provider.loadSchedules();

      final ok = await provider.setRemoteSchedulePaused(
        scheduleId: existing.id,
        paused: true,
      );

      expect(ok, isTrue);
      expect(connectionManager.pauseRemoteScheduleCallCount, 1);
      expect(connectionManager.resumeRemoteScheduleCallCount, 0);
    });

    test('should call resumeRemoteSchedule when resuming', () async {
      final existing = sampleSchedule(enabled: false);
      connectionManager.listSchedulesResult = rd.Success([existing]);
      await provider.loadSchedules();

      final ok = await provider.setRemoteSchedulePaused(
        scheduleId: existing.id,
        paused: false,
      );

      expect(ok, isTrue);
      expect(connectionManager.resumeRemoteScheduleCallCount, 1);
      expect(connectionManager.pauseRemoteScheduleCallCount, 0);
    });

    test(
      'should reload execution queue after mutation when supported',
      () async {
        connectionManager.simulateQueueSupported = true;
        connectionManager.getExecutionQueueCallCount = 0;

        await provider.createRemoteSchedule(sampleSchedule(id: 'draft-queue'));

        expect(connectionManager.createRemoteScheduleCallCount, 1);
        expect(connectionManager.getExecutionQueueCallCount, greaterThan(0));
      },
    );
  });

  group('RemoteSchedulesProvider.cancelSchedule', () {
    test('should use cancelRemoteBackup when runId is active', () async {
      connectionManager.remoteBackupCompleter = Completer<rd.Result<String>>();
      unawaited(provider.executeSchedule(scheduleId));
      await Future<void>.delayed(Duration.zero);

      final ok = await provider.cancelSchedule();

      expect(ok, isTrue);
      expect(connectionManager.lastRunIdForCancel, '${scheduleId}_run-test');
      expect(provider.isExecuting, isFalse);

      connectionManager.remoteBackupCompleter!.complete(const rd.Success(''));
    });
  });
}
