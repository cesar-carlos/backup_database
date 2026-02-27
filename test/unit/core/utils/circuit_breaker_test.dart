import 'dart:async';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/circuit_breaker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CircuitBreaker', () {
    test('allows request when closed', () {
      final breaker = CircuitBreaker(key: 'dest-1');
      expect(breaker.state, CircuitState.closed);
      expect(breaker.allowsRequest, isTrue);
    });

    test('opens after failureThreshold retryable failures', () {
      final breaker = CircuitBreaker(
        key: 'dest-1',
        failureThreshold: 2,
      );

      breaker.recordFailure(
        BackupFailure(
          message: 'fail',
          originalError: TimeoutException('timeout'),
        ),
      );
      expect(breaker.state, CircuitState.closed);

      breaker.recordFailure(
        BackupFailure(
          message: 'fail',
          originalError: TimeoutException('timeout'),
        ),
      );
      expect(breaker.state, CircuitState.open);
      expect(breaker.allowsRequest, isFalse);
    });

    test('does not open on ValidationFailure', () {
      final breaker = CircuitBreaker(
        key: 'dest-1',
        failureThreshold: 2,
      );

      breaker.recordFailure(
        const ValidationFailure(message: 'invalid'),
      );
      breaker.recordFailure(
        const ValidationFailure(message: 'invalid'),
      );
      expect(breaker.state, CircuitState.closed);
    });

    test('resets failure count on success when closed', () {
      final breaker = CircuitBreaker(
        key: 'dest-1',
        failureThreshold: 2,
      );

      breaker.recordFailure(
        BackupFailure(
          message: 'fail',
          originalError: TimeoutException('timeout'),
        ),
      );
      breaker.recordSuccess();
      expect(breaker.state, CircuitState.closed);

      breaker.recordFailure(
        BackupFailure(
          message: 'fail',
          originalError: TimeoutException('timeout'),
        ),
      );
      expect(breaker.state, CircuitState.closed);
    });

    test('transitions to half-open after openDuration when allowsRequest',
        () async {
      final breaker = CircuitBreaker(
        key: 'dest-1',
        failureThreshold: 2,
        openDuration: const Duration(milliseconds: 50),
      );

      breaker.recordFailure(
        BackupFailure(
          message: 'fail',
          originalError: TimeoutException('timeout'),
        ),
      );
      breaker.recordFailure(
        BackupFailure(
          message: 'fail',
          originalError: TimeoutException('timeout'),
        ),
      );
      expect(breaker.state, CircuitState.open);
      expect(breaker.allowsRequest, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(breaker.allowsRequest, isTrue);
      expect(breaker.state, CircuitState.halfOpen);
    });

    test('transitions from half-open to closed on success', () async {
      final breaker = CircuitBreaker(
        key: 'dest-1',
        failureThreshold: 2,
        openDuration: const Duration(milliseconds: 50),
      );

      breaker.recordFailure(
        BackupFailure(
          message: 'fail',
          originalError: TimeoutException('timeout'),
        ),
      );
      breaker.recordFailure(
        BackupFailure(
          message: 'fail',
          originalError: TimeoutException('timeout'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(breaker.allowsRequest, isTrue);
      expect(breaker.state, CircuitState.halfOpen);

      breaker.recordSuccess();
      expect(breaker.state, CircuitState.closed);
    });

    test('reopens from half-open on retryable failure', () async {
      final breaker = CircuitBreaker(
        key: 'dest-1',
        failureThreshold: 2,
        openDuration: const Duration(milliseconds: 50),
        halfOpenSuccessCount: 2,
      );

      breaker.recordFailure(
        BackupFailure(
          message: 'fail',
          originalError: TimeoutException('timeout'),
        ),
      );
      breaker.recordFailure(
        BackupFailure(
          message: 'fail',
          originalError: TimeoutException('timeout'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(breaker.allowsRequest, isTrue);
      expect(breaker.state, CircuitState.halfOpen);

      breaker.recordFailure(
        BackupFailure(
          message: 'fail',
          originalError: TimeoutException('timeout'),
        ),
      );
      expect(breaker.state, CircuitState.open);
    });
  });

  group('CircuitBreakerRegistry', () {
    test('returns same breaker for same destination id', () {
      final registry = CircuitBreakerRegistry();
      final b1 = registry.getBreaker('dest-1');
      final b2 = registry.getBreaker('dest-1');
      expect(identical(b1, b2), isTrue);
    });

    test('returns different breakers for different destination ids', () {
      final registry = CircuitBreakerRegistry();
      final b1 = registry.getBreaker('dest-1');
      final b2 = registry.getBreaker('dest-2');
      expect(identical(b1, b2), isFalse);
    });
  });
}
