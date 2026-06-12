import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/presentation/boot/bootstrap_config.dart';
import 'package:backup_database/presentation/boot/temporary_backup_cleanup_startup_task.dart';
import 'package:backup_database/presentation/boot/ui_scheduler_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const _config = BootstrapConfig(
  appMode: AppMode.server,
  singleInstanceEnabled: true,
  uiSingleInstanceLockFallbackMode: SingleInstanceLockFallbackMode.failOpen,
  uiSchedulerFallbackMode: UiSchedulerFallbackMode.failOpen,
);

void _ignoreLog(String _) {}

void main() {
  group('TemporaryBackupCleanupStartupTask.start', () {
    test('does nothing when scheduler not registered', () async {
      var startCalled = false;
      await TemporaryBackupCleanupStartupTask(
        isSchedulerRegistered: () => false,
        shouldSkipCleanup: (_) async => false,
        startScheduler: () {
          startCalled = true;
        },
        logInfo: _ignoreLog,
        logWarning: (_, [_, _]) {},
      ).start(_config);

      expect(startCalled, isFalse);
    });

    test('starts scheduler when registered and policy allows', () async {
      var startCalled = false;
      await TemporaryBackupCleanupStartupTask(
        isSchedulerRegistered: () => true,
        shouldSkipCleanup: (_) async => false,
        startScheduler: () {
          startCalled = true;
        },
        logInfo: _ignoreLog,
        logWarning: (_, [_, _]) {},
      ).start(_config);

      expect(startCalled, isTrue);
    });

    test('skips scheduler when policy blocks UI cleanup', () async {
      var startCalled = false;
      final infoLogs = <String>[];
      await TemporaryBackupCleanupStartupTask(
        isSchedulerRegistered: () => true,
        shouldSkipCleanup: (_) async => true,
        startScheduler: () {
          startCalled = true;
        },
        logInfo: infoLogs.add,
        logWarning: (_, [_, _]) {},
      ).start(_config);

      expect(startCalled, isFalse);
      expect(
        infoLogs.single,
        contains(
          'temp_backup_cleanup_skipped=windows_service_installed_and_running',
        ),
      );
    });

    test('logs warning and swallows scheduler failure', () async {
      final warnings = <String>[];
      await TemporaryBackupCleanupStartupTask(
        isSchedulerRegistered: () => true,
        shouldSkipCleanup: (_) async => false,
        startScheduler: () => throw StateError('cleanup boom'),
        logInfo: _ignoreLog,
        logWarning: (message, [_, _]) => warnings.add(message),
      ).start(_config);

      expect(
        warnings.first,
        contains('Erro ao iniciar limpeza periodica de temporarios locais'),
      );
    });
  });
}
