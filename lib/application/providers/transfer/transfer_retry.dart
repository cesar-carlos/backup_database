import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';

class TransferRetry {
  TransferRetry._();

  static Future<T> execute<T>(
    Future<T> Function() operation, {
    int maxAttempts = SocketConfig.maxRetries,
    Duration initialDelay = SocketConfig.downloadRetryInitialDelay,
    Duration maxDelay = SocketConfig.downloadRetryMaxDelay,
    int backoffMultiplier = SocketConfig.downloadRetryBackoffMultiplier,
    String? operationName,
  }) async {
    var attempt = 0;
    var delay = initialDelay;

    while (true) {
      attempt++;
      final name = operationName ?? 'Operation';

      try {
        return await operation();
      } on Object catch (e, st) {
        final isLastAttempt = attempt >= maxAttempts;

        LoggerService.warning(
          '$name failed (attempt $attempt/$maxAttempts): $e',
          e,
          st,
        );

        if (isLastAttempt) {
          LoggerService.error('$name failed after $maxAttempts attempts');
          rethrow;
        }

        LoggerService.info(
          'Retrying $name in ${delay.inSeconds}s '
          '(attempt ${attempt + 1}/$maxAttempts)',
        );

        await Future.delayed(delay);

        final nextDelayMs = delay.inMilliseconds * backoffMultiplier;
        final nextDelay = Duration(milliseconds: nextDelayMs);

        delay = nextDelay < maxDelay ? nextDelay : maxDelay;
      }
    }
  }
}
