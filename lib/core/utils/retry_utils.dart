import 'dart:async';
import 'dart:math';

import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

final _random = Random();

bool isRetryableFailure(Object failure) {
  // 1) Validação semântica nunca retentável.
  if (failure is ValidationFailure) return false;

  // 2) Decisão por failure.code (lista whitelisted explícita).
  if (failure is Failure && failure.code != null) {
    final decision = _retryDecisionFromFailureCode(failure.code!);
    if (decision != null) return decision;
  }

  // 3) Inspeção da exceção original embrulhada (timeout, socket, etc.).
  if (failure is Failure && failure.originalError != null) {
    if (_isRetryableOriginalError(failure.originalError!)) return true;
  }

  // 4) Exception direta, sem wrap em Failure.
  if (failure is TimeoutException) return true;

  // 5) Fallback heurístico no toString — última linha de defesa para
  //    erros que ainda não foram modelados como `Failure` tipado.
  return _toStringSuggestsRetry(failure);
}

bool? _retryDecisionFromFailureCode(String code) {
  if (code == FailureCodes.ftpIntegrityValidationInconclusive ||
      code == FailureCodes.integrityValidationInconclusive) {
    return true;
  }
  if (code == FailureCodes.uploadCancelled ||
      code == FailureCodes.backupCancelled ||
      code == FailureCodes.validationFailed ||
      code == FailureCodes.ftpIntegrityValidationFailed) {
    return false;
  }
  return null;
}

bool _isRetryableOriginalError(Object original) {
  if (original is TimeoutException) return true;

  final originalStr = original.toString();
  if (originalStr.contains('SocketException')) return true;
  if (originalStr.contains('Connection') ||
      originalStr.contains('connection')) {
    return true;
  }
  if (originalStr.contains('timeout') || originalStr.contains('Timeout')) {
    return true;
  }
  // 5xx temporários comuns em proxies/load balancers.
  if (originalStr.contains('503') ||
      originalStr.contains('502') ||
      originalStr.contains('504')) {
    return true;
  }
  return false;
}

bool _toStringSuggestsRetry(Object failure) {
  final msg = failure.toString().toLowerCase();
  return msg.contains('socket') ||
      msg.contains('connection') ||
      msg.contains('timeout') ||
      msg.contains('network');
}

Duration addJitter(Duration base, double jitterFactor) {
  final jitter =
      base.inMilliseconds * jitterFactor * (_random.nextDouble() * 2 - 1);
  final ms = (base.inMilliseconds + jitter).round().clamp(
    100,
    base.inMilliseconds * 2,
  );
  return Duration(milliseconds: ms);
}

/// Executa [operation] com retry exponencial em falhas retryable.
///
/// Aceita [isCancelled] opcional: quando ele retorna `true`, o retry é
/// abortado imediatamente — **inclusive durante o sleep de backoff**,
/// que é dividido em fatias curtas para reagir a cancelamento em tempo
/// hábil. Antes, um cancelamento durante um backoff de 60s + 120s
/// poderia ficar bloqueado por minutos antes de efetivar.
Future<rd.Result<T>> executeResultWithRetry<T extends Object>({
  required Future<rd.Result<T>> Function() operation,
  int maxAttempts = DestinationRetryConstants.maxAttempts,
  Duration initialDelay = DestinationRetryConstants.initialDelay,
  Duration maxDelay = DestinationRetryConstants.maxDelay,
  int backoffMultiplier = DestinationRetryConstants.backoffMultiplier,
  double jitterFactor = DestinationRetryConstants.jitterFactor,
  String? operationName,
  bool Function()? isCancelled,
}) async {
  var attempt = 0;
  var delay = initialDelay;
  final name = operationName ?? 'Operation';

  while (true) {
    if (isCancelled != null && isCancelled()) {
      return const rd.Failure(
        BackupFailure(
          message:
              'Operação cancelada pelo usuário antes da próxima tentativa.',
          code: FailureCodes.uploadCancelled,
        ),
      );
    }

    attempt++;
    final result = await operation();

    if (result.isSuccess()) {
      if (attempt > 1) {
        LoggerService.info(
          '$name succeeded on attempt $attempt/$maxAttempts',
        );
      }
      return result;
    }

    final failure = result.exceptionOrNull()!;
    final isLastAttempt = attempt >= maxAttempts;
    final canRetry = isRetryableFailure(failure);

    final failureLog = failure is Failure
        ? failure.message
        : failure.toString();
    LoggerService.warning(
      '$name failed (attempt $attempt/$maxAttempts): $failureLog',
      failure,
    );

    if (isLastAttempt || !canRetry) {
      return result;
    }

    final delayWithJitter = addJitter(delay, jitterFactor);
    LoggerService.info(
      'Retrying $name in ${delayWithJitter.inMilliseconds}ms '
      '(attempt ${attempt + 1}/$maxAttempts)',
    );

    final canceledDuringBackoff = await _sleepWithCancellation(
      delayWithJitter,
      isCancelled,
    );
    if (canceledDuringBackoff) {
      return const rd.Failure(
        BackupFailure(
          message: 'Operação cancelada pelo usuário durante o backoff.',
          code: FailureCodes.uploadCancelled,
        ),
      );
    }

    final nextDelayMs = delay.inMilliseconds * backoffMultiplier;
    delay = Duration(
      milliseconds: nextDelayMs.clamp(0, maxDelay.inMilliseconds),
    );
    if (delay > maxDelay) delay = maxDelay;
  }
}

/// Intervalo entre checagens de cancelamento durante o sleep do backoff.
const Duration _cancelPollInterval = Duration(milliseconds: 250);

/// Dorme por `total`, checando `isCancelled` a cada `_cancelPollInterval`.
/// Retorna `true` se foi cancelado durante o sleep; `false` caso contrário.

Future<bool> _sleepWithCancellation(
  Duration total,
  bool Function()? isCancelled,
) async {
  if (isCancelled == null) {
    await Future.delayed(total);
    return false;
  }
  var remaining = total;
  while (remaining > Duration.zero) {
    if (isCancelled()) return true;
    final slice = remaining < _cancelPollInterval
        ? remaining
        : _cancelPollInterval;
    await Future.delayed(slice);
    remaining -= slice;
  }
  return isCancelled();
}
