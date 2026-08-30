import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract final class EmailDeliveryBatcher {
  static const int maxParallelRecipientSends = 4;
  static const int maxParallelConfigs = 3;

  static Future<List<R>> runInBatches<T, R>(
    List<T> items,
    int concurrencyLimit,
    Future<R> Function(T item) task,
  ) async {
    if (items.isEmpty) {
      return const [];
    }

    final results = <R>[];
    for (var index = 0; index < items.length; index += concurrencyLimit) {
      final batchEnd = (index + concurrencyLimit > items.length)
          ? items.length
          : index + concurrencyLimit;
      final batch = items.sublist(index, batchEnd);
      final batchResults = await Future.wait(batch.map(task));
      results.addAll(batchResults);
    }
    return results;
  }

  static Future<rd.Result<bool>> sendToConfigs({
    required List<EmailConfig> configs,
    required String eventType,
    required Future<ConfigSendOutcome> Function(EmailConfig config)
    processConfig,
  }) async {
    final enabled = configs.where((cfg) => cfg.enabled).toList();
    if (enabled.isEmpty) {
      return const rd.Success(false);
    }

    final outcomes = await runInBatches<EmailConfig, ConfigSendOutcome>(
      enabled,
      maxParallelConfigs,
      (config) async {
        final outcome = await processConfig(config);
        if (outcome.summary != null) {
          logDeliverySummary(
            configId: config.id,
            eventType: eventType,
            summary: outcome.summary!,
          );
        } else if (outcome.failure != null) {
          LoggerService.warning(
            'Falha ao processar configuracao ${config.id}: '
            '${outcome.failure}',
          );
        }
        return outcome;
      },
    );

    var sentAny = false;
    Exception? firstFailure;
    for (final outcome in outcomes) {
      if (outcome.sent) sentAny = true;
      if (outcome.failure != null) {
        firstFailure ??= toException(outcome.failure!);
      }
    }

    if (sentAny) return const rd.Success(true);
    if (firstFailure != null) return rd.Failure(firstFailure);
    return const rd.Success(false);
  }

  static DeliverySendSummary summarizeDeliveryResults(
    List<RecipientDeliveryResult> results,
  ) {
    var sent = 0;
    var failed = 0;
    var skipped = 0;
    Exception? firstFailure;

    for (final result in results) {
      if (result.isSent) {
        sent++;
      } else if (result.isFailed) {
        failed++;
        firstFailure ??= result.failure;
      } else {
        skipped++;
      }
    }

    return DeliverySendSummary(
      attemptedCount: results.length,
      sentCount: sent,
      failedCount: failed,
      skippedCount: skipped,
      firstFailure: firstFailure,
    );
  }

  static void logDeliverySummary({
    required String configId,
    required String eventType,
    required DeliverySendSummary summary,
  }) {
    LoggerService.info(
      '[NotificationService] Resumo de envio | '
      'configId=$configId '
      'event=$eventType '
      'attempted=${summary.attemptedCount} '
      'sent=${summary.sentCount} '
      'failed=${summary.failedCount} '
      'skipped=${summary.skippedCount}',
    );
  }

  static Exception toException(Object failure) {
    if (failure is Exception) {
      return failure;
    }
    return Exception(failureUserMessage(failure));
  }
}

class RecipientDeliveryResult {
  const RecipientDeliveryResult._({
    required this.recipientEmail,
    required this.state,
    this.failure,
    this.reason,
  });

  factory RecipientDeliveryResult.sent({required String recipientEmail}) {
    return RecipientDeliveryResult._(
      recipientEmail: recipientEmail,
      state: RecipientDeliveryState.sent,
    );
  }

  factory RecipientDeliveryResult.failed({
    required String recipientEmail,
    required Exception failure,
  }) {
    return RecipientDeliveryResult._(
      recipientEmail: recipientEmail,
      failure: failure,
      state: RecipientDeliveryState.failed,
    );
  }

  factory RecipientDeliveryResult.skipped({
    required String recipientEmail,
    required String reason,
  }) {
    return RecipientDeliveryResult._(
      recipientEmail: recipientEmail,
      reason: reason,
      state: RecipientDeliveryState.skipped,
    );
  }

  factory RecipientDeliveryResult.fromEmailSendResult(
    rd.Result<bool> sendResult, {
    required String recipientEmail,
  }) {
    return sendResult.fold(
      (sent) => sent
          ? RecipientDeliveryResult.sent(recipientEmail: recipientEmail)
          : RecipientDeliveryResult.skipped(
              recipientEmail: recipientEmail,
              reason: 'Envio não realizado pelo serviço SMTP',
            ),
      (failure) => RecipientDeliveryResult.failed(
        recipientEmail: recipientEmail,
        failure: EmailDeliveryBatcher.toException(failure),
      ),
    );
  }

  final String recipientEmail;
  final Exception? failure;
  final String? reason;
  final RecipientDeliveryState state;

  bool get isSent => state == RecipientDeliveryState.sent;
  bool get isFailed => state == RecipientDeliveryState.failed;
}

class DeliverySendSummary {
  const DeliverySendSummary({
    required this.attemptedCount,
    required this.sentCount,
    required this.failedCount,
    required this.skippedCount,
    required this.firstFailure,
  });

  final int attemptedCount;
  final int sentCount;
  final int failedCount;
  final int skippedCount;
  final Exception? firstFailure;
}

class ConfigSendOutcome {
  const ConfigSendOutcome._({
    required this.sent,
    this.summary,
    this.failure,
  });

  factory ConfigSendOutcome.empty() => const ConfigSendOutcome._(sent: false);

  factory ConfigSendOutcome.failure(Object failure) =>
      ConfigSendOutcome._(sent: false, failure: failure);

  factory ConfigSendOutcome.fromSummary(DeliverySendSummary summary) =>
      ConfigSendOutcome._(
        sent: summary.sentCount > 0,
        summary: summary,
        failure: summary.firstFailure,
      );

  final bool sent;
  final DeliverySendSummary? summary;
  final Object? failure;
}

enum RecipientDeliveryState { sent, failed, skipped }
