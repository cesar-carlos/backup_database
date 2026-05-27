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
  }) : _key = key,
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
  int _halfOpenInFlight = 0;
  DateTime? _openedAt;

  /// Permissões simultâneas durante half-open. `1` evita que múltiplas
  /// requisições paralelas (em `uploadToAllDestinations` ou retry
  /// concorrente) saturem um destino frágil enquanto o breaker deveria
  /// estar testando recovery com uma única requisição.
  static const int _halfOpenMaxInFlight = 1;

  CircuitState get state => _state;

  /// Verifica se há permissão para enviar uma requisição **sem** mutar
  /// estado. Use [tryAcquire] quando quiser reservar um slot de probe
  /// em half-open (necessário para o gating real).
  bool get allowsRequest {
    switch (_state) {
      case CircuitState.closed:
        return true;
      case CircuitState.open:
        if (_openedAt != null &&
            DateTime.now().difference(_openedAt!) >= _openDuration) {
          _transitionToHalfOpen();
          return _halfOpenInFlight < _halfOpenMaxInFlight;
        }
        return false;
      case CircuitState.halfOpen:
        return _halfOpenInFlight < _halfOpenMaxInFlight;
    }
  }

  /// Tenta reservar um slot de requisição. Retorna `true` se permitido
  /// (e em half-open incrementa o counter in-flight, que deve ser
  /// liberado depois via [recordSuccess]/[recordFailure]).
  ///
  /// Em closed: sempre `true`.
  /// Em open com `openDuration` vencida: transiciona para half-open e
  /// reserva o slot.
  /// Em half-open: reserva se houver slot livre.
  bool tryAcquire() {
    switch (_state) {
      case CircuitState.closed:
        return true;
      case CircuitState.open:
        if (_openedAt != null &&
            DateTime.now().difference(_openedAt!) >= _openDuration) {
          _transitionToHalfOpen();
          if (_halfOpenInFlight < _halfOpenMaxInFlight) {
            _halfOpenInFlight++;
            return true;
          }
          return false;
        }
        return false;
      case CircuitState.halfOpen:
        if (_halfOpenInFlight < _halfOpenMaxInFlight) {
          _halfOpenInFlight++;
          return true;
        }
        return false;
    }
  }

  void recordSuccess() {
    switch (_state) {
      case CircuitState.closed:
        _failureCount = 0;
      case CircuitState.open:
        // Sucesso em estado open é inesperado (caller ignorou tryAcquire).
        // Mantém estado aberto até o timer vencer — não fechamos
        // implicitamente sem passar por half-open.
        LoggerService.warning(
          'Circuit breaker $_key: recordSuccess em estado OPEN ignorado '
          '(caller deve consultar tryAcquire/allowsRequest antes do request).',
        );
      case CircuitState.halfOpen:
        if (_halfOpenInFlight > 0) _halfOpenInFlight--;
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
        // Não renova _openedAt: antes este caminho fazia
        // `_openedAt = DateTime.now()` em cada falha em estado open,
        // estendendo o cooldown indefinidamente sob falhas contínuas
        // de outros callers (que sequer deveriam estar consultando o
        // breaker neste estado). Agora apenas ignoramos.
        break;
      case CircuitState.halfOpen:
        if (_halfOpenInFlight > 0) _halfOpenInFlight--;
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
    _halfOpenInFlight = 0;
    LoggerService.info('Circuit breaker $_key: HALF-OPEN (testing recovery)');
  }

  void _transitionToClosed() {
    _state = CircuitState.closed;
    _failureCount = 0;
    _halfOpenSuccessCountCurrent = 0;
    _halfOpenInFlight = 0;
    _openedAt = null;
    LoggerService.info('Circuit breaker $_key: CLOSED');
  }
}

class CircuitBreakerRegistry {
  CircuitBreakerRegistry({
    int failureThreshold = CircuitBreakerConstants.failureThreshold,
    Duration openDuration = CircuitBreakerConstants.openDuration,
    int halfOpenSuccessCount = CircuitBreakerConstants.halfOpenSuccessCount,
  }) : _failureThreshold = failureThreshold,
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
