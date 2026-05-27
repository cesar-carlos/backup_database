import 'dart:async';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/utils/retry_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart' as rd;

void main() {
  group('isRetryableFailure', () {
    test('returns false for ValidationFailure', () {
      expect(
        isRetryableFailure(const ValidationFailure(message: 'invalid')),
        isFalse,
      );
    });

    test('returns true for TimeoutException', () {
      expect(
        isRetryableFailure(TimeoutException('timed out')),
        isTrue,
      );
    });

    test('returns true for Failure with timeout in originalError', () {
      expect(
        isRetryableFailure(
          BackupFailure(
            message: 'backup failed',
            originalError: TimeoutException('timed out'),
          ),
        ),
        isTrue,
      );
    });

    test('returns true for Failure with connection in message', () {
      expect(
        isRetryableFailure(
          const NetworkFailure(message: 'Connection refused'),
        ),
        isTrue,
      );
    });

    test('returns false for BackupFailure without retryable signals', () {
      expect(
        isRetryableFailure(
          const BackupFailure(message: 'Invalid config'),
        ),
        isFalse,
      );
    });

    test('returns false for Failure with uploadCancelled code', () {
      expect(
        isRetryableFailure(
          const BackupFailure(
            message: 'Upload cancelado',
            code: FailureCodes.uploadCancelled,
          ),
        ),
        isFalse,
      );
    });

    test('returns false for Failure with backupCancelled code', () {
      expect(
        isRetryableFailure(
          const BackupFailure(
            message: 'Backup cancelado',
            code: FailureCodes.backupCancelled,
          ),
        ),
        isFalse,
      );
    });

    test('returns false for Failure with validationFailed code', () {
      expect(
        isRetryableFailure(
          const ValidationFailure(
            message: 'invalid',
            code: FailureCodes.validationFailed,
          ),
        ),
        isFalse,
      );
    });
  });

  group('executeResultWithRetry', () {
    test('returns success on first attempt', () async {
      var attempts = 0;
      final result = await executeResultWithRetry(
        operation: () async {
          attempts++;
          return const rd.Success(42);
        },
        operationName: 'test op',
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull(), 42);
      expect(attempts, 1);
    });

    test('retries on retryable failure and succeeds', () async {
      var attempts = 0;
      final result = await executeResultWithRetry<int>(
        operation: () async {
          attempts++;
          if (attempts < 2) {
            return rd.Failure(
              BackupFailure(
                message: 'fail',
                originalError: TimeoutException('timeout'),
              ),
            );
          }
          return const rd.Success(1);
        },
        operationName: 'test op',
      );

      expect(result.isSuccess(), isTrue);
      expect(attempts, 2);
    });

    test('does not retry on ValidationFailure', () async {
      var attempts = 0;
      final result = await executeResultWithRetry<int>(
        operation: () async {
          attempts++;
          return const rd.Failure(
            ValidationFailure(message: 'invalid'),
          );
        },
        operationName: 'test op',
      );

      expect(result.isError(), isTrue);
      expect(attempts, 1);
    });

    test('stops after maxAttempts', () async {
      var attempts = 0;
      final result = await executeResultWithRetry<int>(
        operation: () async {
          attempts++;
          return rd.Failure(
            BackupFailure(
              message: 'fail',
              originalError: TimeoutException('timeout'),
            ),
          );
        },
        operationName: 'test op',
      );

      expect(result.isError(), isTrue);
      expect(attempts, 3);
    });

    test('does not retry on uploadCancelled', () async {
      var attempts = 0;
      final result = await executeResultWithRetry<int>(
        operation: () async {
          attempts++;
          return const rd.Failure(
            BackupFailure(
              message: 'Upload cancelado',
              code: FailureCodes.uploadCancelled,
            ),
          );
        },
        operationName: 'test op',
      );

      expect(result.isError(), isTrue);
      expect(attempts, 1);
    });

    test('does not retry on backupCancelled', () async {
      var attempts = 0;
      final result = await executeResultWithRetry<int>(
        operation: () async {
          attempts++;
          return const rd.Failure(
            BackupFailure(
              message: 'Backup cancelado',
              code: FailureCodes.backupCancelled,
            ),
          );
        },
        operationName: 'test op',
      );

      expect(result.isError(), isTrue);
      expect(attempts, 1);
    });

    test(
      'aborts immediately when isCancelled() returns true before first attempt',
      () async {
        var attempts = 0;
        final result = await executeResultWithRetry<int>(
          operation: () async {
            attempts++;
            return const rd.Success(1);
          },
          operationName: 'test op',
          isCancelled: () => true,
        );

        expect(result.isError(), isTrue);
        expect(attempts, 0, reason: 'operation must not run after cancel');
        final f = result.exceptionOrNull()! as Failure;
        expect(f.code, FailureCodes.uploadCancelled);
      },
    );

    test('aborts during backoff sleep (does not wait full delay)', () async {
      var attempts = 0;
      var cancelToggle = false;

      // 1ª tentativa: falha retryable. 2ª tentativa nunca acontece
      // porque cancel é ativado durante o backoff de 100ms.
      final stopwatch = Stopwatch()..start();
      final result = await executeResultWithRetry<int>(
        operation: () async {
          attempts++;
          // Ativa cancel logo após a 1ª tentativa (será polled durante
          // o sleep, em fatias de 250ms).
          Future.delayed(const Duration(milliseconds: 50), () {
            cancelToggle = true;
          });
          return rd.Failure(TimeoutException('transient'));
        },
        operationName: 'test op',
        initialDelay: const Duration(seconds: 30),
        maxAttempts: 5,
        isCancelled: () => cancelToggle,
      );
      stopwatch.stop();

      expect(attempts, 1, reason: 'should only run first attempt');
      expect(result.isError(), isTrue);
      final f = result.exceptionOrNull()! as Failure;
      expect(f.code, FailureCodes.uploadCancelled);
      expect(
        stopwatch.elapsed.inSeconds,
        lessThan(2),
        reason: 'cancel must short-circuit the 30s backoff sleep',
      );
    });
  });
}
