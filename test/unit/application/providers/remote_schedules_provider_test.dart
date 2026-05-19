import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
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
