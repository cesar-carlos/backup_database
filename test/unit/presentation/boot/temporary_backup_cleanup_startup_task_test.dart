import 'package:backup_database/presentation/boot/temporary_backup_cleanup_startup_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TemporaryBackupCleanupStartupTask.start', () {
    test('does nothing when scheduler not registered', () {
      var startCalled = false;
      TemporaryBackupCleanupStartupTask(
        isSchedulerRegistered: () => false,
        startScheduler: () {
          startCalled = true;
        },
        logWarning: (_, [_, _]) {},
      ).start();

      expect(startCalled, isFalse);
    });

    test('starts scheduler when registered', () {
      var startCalled = false;
      TemporaryBackupCleanupStartupTask(
        isSchedulerRegistered: () => true,
        startScheduler: () {
          startCalled = true;
        },
        logWarning: (_, [_, _]) {},
      ).start();

      expect(startCalled, isTrue);
    });

    test('logs warning and swallows scheduler failure', () {
      final warnings = <String>[];
      TemporaryBackupCleanupStartupTask(
        isSchedulerRegistered: () => true,
        startScheduler: () => throw StateError('cleanup boom'),
        logWarning: (message, [_, _]) => warnings.add(message),
      ).start();

      expect(
        warnings.first,
        contains('Erro ao iniciar limpeza periodica de temporarios locais'),
      );
    });
  });
}
