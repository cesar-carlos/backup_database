import 'dart:io';

import 'package:backup_database/application/services/notification/email_delivery_batcher.dart';
import 'package:backup_database/application/services/notification/email_test_failure_classifier.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_email_test_audit_repository.dart';

class NotificationAuditWriter {
  NotificationAuditWriter({
    required this._backupLogRepository,
    required this._emailTestAuditRepository,
  });

  final IBackupLogRepository _backupLogRepository;
  final IEmailTestAuditRepository _emailTestAuditRepository;

  Future<void> saveBackupDeliveryAuditLog({
    required String configId,
    required EmailNotificationTarget target,
    required String eventType,
    required RecipientDeliveryResult result,
    String? historyId,
  }) async {
    final level = result.isFailed ? LogLevel.error : LogLevel.info;
    final status = result.isSent
        ? 'success'
        : result.isFailed
        ? 'failure'
        : 'skipped';
    final message =
        'Notificação $eventType para ${target.recipientEmail}: $status';
    final detailsBuffer = StringBuffer()
      ..write('configId=$configId;')
      ..write('targetId=${target.id};')
      ..write('recipient=${target.recipientEmail};')
      ..write('event=$eventType;')
      ..write('status=$status');
    if (result.reason != null && result.reason!.trim().isNotEmpty) {
      detailsBuffer.write(';reason=${result.reason!.trim()}');
    }
    if (result.failure != null) {
      detailsBuffer.write(';error=${result.failure}');
    }

    final log = BackupLog(
      backupHistoryId: historyId,
      level: level,
      category: LogCategory.audit,
      message: message,
      details: detailsBuffer.toString(),
    );
    final createResult = await _backupLogRepository.create(log);
    createResult.fold((_) {}, (failure) {
      LoggerService.warning(
        '[NotificationService] Falha ao persistir auditoria de entrega: '
        '$failure',
      );
    });
  }

  Future<void> saveEmailTestAudit({
    required EmailConfig config,
    required String correlationId,
    required String recipientEmail,
    required String senderEmail,
    Object? failure,
  }) async {
    final normalizedCorrelationId = correlationId.trim();
    if (normalizedCorrelationId.isEmpty) {
      return;
    }

    final normalizedRecipient = recipientEmail.trim();
    if (normalizedRecipient.isEmpty && failure == null) {
      return;
    }

    final audit = EmailTestAudit(
      configId: config.id,
      correlationId: normalizedCorrelationId,
      recipientEmail: normalizedRecipient,
      senderEmail: senderEmail.trim(),
      smtpServer: config.smtpServer,
      smtpPort: config.smtpPort,
      status: failure == null ? 'success' : 'failure',
      errorType: EmailTestFailureClassifier.classify(failure),
      errorMessage: failure == null ? null : failureUserMessage(failure),
    );

    final result = await _emailTestAuditRepository.create(audit);
    result.fold(
      (_) => null,
      (saveFailure) => LoggerService.warning(
        '[NotificationService] Falha ao persistir auditoria SMTP: $saveFailure',
      ),
    );
  }

  Future<void> cleanupTempLog(String? logPath) async {
    if (logPath == null) return;
    try {
      final file = File(logPath);
      final parent = file.parent;
      if (await file.exists()) {
        await file.delete();
      }
      if (await parent.exists() &&
          parent.path.contains('backup_logs_') &&
          (await parent.list().isEmpty)) {
        await parent.delete();
      }
    } on Object catch (e) {
      LoggerService.debug(
        '[NotificationService] Falha ao limpar log temporário '
        '$logPath: $e',
      );
    }
  }
}
