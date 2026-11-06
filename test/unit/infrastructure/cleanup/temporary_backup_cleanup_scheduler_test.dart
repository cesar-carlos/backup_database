import 'dart:async';

import 'package:backup_database/domain/services/i_temporary_backup_cleanup_service.dart';
import 'package:backup_database/infrastructure/cleanup/temporary_backup_cleanup_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Cleanup extends Mock implements ITemporaryBackupCleanupService {}

void main() {
  test('invalid timer interval cannot start a tight cleanup loop', () {
    final service = _Cleanup();
    final scheduler = TemporaryBackupCleanupScheduler(service);
    expect(() => scheduler.start(interval: Duration.zero), throwsArgumentError);
    expect(
      () => scheduler.start(interval: const Duration(seconds: -1)),
      throwsArgumentError,
    );
    expect(scheduler.isRunning, isFalse);
    verifyNever(service.cleanupOrphanedFailedUploads);
  });
  test('periodic cleanup does not overlap and resumes after failure', () async {
    final service = _Cleanup();
    final first = Completer<TemporaryBackupCleanupResult>();
    var calls = 0;
    when(service.cleanupOrphanedFailedUploads).thenAnswer((_) {
      calls++;
      if (calls == 1) return first.future;
      return Future.value(
        const TemporaryBackupCleanupResult(deletedCount: 0, bytesFreed: 0),
      );
    });
    final scheduler = TemporaryBackupCleanupScheduler(service);
    try {
      scheduler.start(interval: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(calls, 1);
      first.completeError(StateError('interrupted'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(calls, greaterThan(1));
      scheduler.stop();
      final stoppedCalls = calls;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls, stoppedCalls);
    } finally {
      scheduler.stop();
    }
  });
}
