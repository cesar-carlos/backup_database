import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/retry_utils.dart';

enum CircuitState { closed, open, halfOpen }

class CircuitBreaker {
  CircuitBreaker({
    required String key,
    int failureThreshold = CircuitBreakerConstants.failureThreshold,
    Duration openDuration = CircuitBreakerConstants.openDuration,
    int halfOpenSuccessCount = CircuitBreakerConstants.halfOpenSuccessCount,
  })  : _key = key,
        _failureThreshold = failureThreshold,
        _openDuration = openDuration,
        _halfOpenSuccessCount = halfOpenSuccessCount;

  final String _key;
  final int _failureThreshold;
  final Duration _openDuration;
  final int _halfOpenSuccessCount;

  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  int _halfOpenSuccessCountCurrent = 0;
  DateTime? _openedAt;

  CircuitState get state => _state;

  bool get allowsRequest {
    switch (_state) {
      case CircuitState.closed:
        return true;
      case CircuitState.open:
        if (_openedAt != null &&
            DateTime.now().difference(_openedAt!) >= _openDuration) {
          _transitionToHalfOpen();
          return true;
        }
        return false;
      case CircuitState.halfOpen:
        return true;
    }
  }

  void recordSuccess() {
    switch (_state) {
      case CircuitState.closed:
        _failureCount = 0;
      case CircuitState.open:
      case CircuitState.halfOpen:
        _halfOpenSuccessCountCurrent++;
        if (_halfOpenSuccessCountCurrent >= _halfOpenSuccessCount) {
          _transitionToClosed();
        }
    }
  }

  void recordFailure(Object failure) {
    if (!isRetryableFailure(failure)) {
      return;
    }
    switch (_state) {
      case CircuitState.closed:
        _failureCount++;
        if (_failureCount >= _failureThreshold) {
          _transitionToOpen();
        }
      case CircuitState.open:
        _openedAt = DateTime.now();
      case CircuitState.halfOpen:
        _transitionToOpen();
    }
  }

  void _transitionToOpen() {
    _state = CircuitState.open;
    _openedAt = DateTime.now();
    LoggerService.warning(
      'Circuit breaker $_key: OPEN (failures: $_failureCount)',
    );
  }

  void _transitionToHalfOpen() {
    _state = CircuitState.halfOpen;
    _halfOpenSuccessCountCurrent = 0;
    LoggerService.info('Circuit breaker $_key: HALF-OPEN (testing recovery)');
  }

  void _transitionToClosed() {
    _state = CircuitState.closed;
    _failureCount = 0;
    _halfOpenSuccessCountCurrent = 0;
    _openedAt = null;
    LoggerService.info('Circuit breaker $_key: CLOSED');
  }
}

class CircuitBreakerRegistry {
  CircuitBreakerRegistry({
    int failureThreshold = CircuitBreakerConstants.failureThreshold,
    Duration openDuration = CircuitBreakerConstants.openDuration,
    int halfOpenSuccessCount = CircuitBreakerConstants.halfOpenSuccessCount,
  })  : _failureThreshold = failureThreshold,
        _openDuration = openDuration,
        _halfOpenSuccessCount = halfOpenSuccessCount;

  final int _failureThreshold;
  final Duration _openDuration;
  final int _halfOpenSuccessCount;

  final Map<String, CircuitBreaker> _breakers = {};

  CircuitBreaker getBreaker(String destinationId) {
    return _breakers.putIfAbsent(
      destinationId,
      () => CircuitBreaker(
        key: destinationId,
        failureThreshold: _failureThreshold,
        openDuration: _openDuration,
        halfOpenSuccessCount: _halfOpenSuccessCount,
      ),
    );
  }
}
