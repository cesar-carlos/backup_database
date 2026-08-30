import 'dart:io';

import 'package:backup_database/application/services/notification/email_delivery_batcher.dart';
import 'package:backup_database/application/services/notification/notification_audit_writer.dart';
import 'package:backup_database/application/services/notification/notification_event_policy.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/domain/services/i_email_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class BackupNotificationDispatcher {
  BackupNotificationDispatcher({
    required this._targetRepository,
    required this._emailService,
    required this._backupLogRepository,
    required this._auditWriter,
  });

  final IEmailNotificationTargetRepository _targetRepository;
  final IEmailService _emailService;
  final IBackupLogRepository _backupLogRepository;
  final NotificationAuditWriter _auditWriter;

  Future<rd.Result<bool>> sendHistoryWithConfigs(
    List<EmailConfig> configs,
    BackupHistory history,
  ) {
    return EmailDeliveryBatcher.sendToConfigs(
      configs: configs,
      eventType: NotificationEventPolicy.eventTypeFor(history.status),
      processConfig: (config) async {
        final logPath = config.attachLog
            ? await _exportLogsForBackup(history.id)
            : null;
        try {
          final targetResult = await _targetRepository.getByConfigId(config.id);
          if (targetResult.isError()) {
            return ConfigSendOutcome.failure(
              targetResult.exceptionOrNull() ??
                  Exception('Falha ao carregar destinatarios'),
            );
          }
          final targets = targetResult.getOrElse((_) => const []);
          if (targets.isEmpty) {
            LoggerService.info(
              'Configuracao ${config.id} sem destinatarios ativos '
              'para envio.',
            );
            return ConfigSendOutcome.empty();
          }
          final summary = await _sendHistoryToTargets(
            config,
            targets,
            history,
            logPath,
          );
          return ConfigSendOutcome.fromSummary(summary);
        } finally {
          await _auditWriter.cleanupTempLog(logPath);
        }
      },
    );
  }

  Future<rd.Result<bool>> sendWarningWithConfigs(
    List<EmailConfig> configs,
    String databaseName,
    String message,
  ) {
    return EmailDeliveryBatcher.sendToConfigs(
      configs: configs,
      eventType: 'backup_warning',
      processConfig: (config) async {
        final targetResult = await _targetRepository.getByConfigId(config.id);
        if (targetResult.isError()) {
          return ConfigSendOutcome.failure(
            targetResult.exceptionOrNull() ??
                Exception('Falha ao carregar destinatarios'),
          );
        }
        final targets = targetResult.getOrElse((_) => const []);
        if (targets.isEmpty) {
          LoggerService.info(
            'Configuracao ${config.id} sem destinatarios ativos '
            'para envio de aviso.',
          );
          return ConfigSendOutcome.empty();
        }
        final summary = await _sendWarningToTargets(
          config,
          targets,
          databaseName,
          message,
        );
        return ConfigSendOutcome.fromSummary(summary);
      },
    );
  }

  Future<DeliverySendSummary> _sendHistoryToTargets(
    EmailConfig config,
    List<EmailNotificationTarget> targets,
    BackupHistory history,
    String? logPath,
  ) async {
    final enabledTargets = targets.where((target) => target.enabled).toList();
    final results =
        await EmailDeliveryBatcher.runInBatches<
          EmailNotificationTarget,
          RecipientDeliveryResult
        >(
          enabledTargets,
          EmailDeliveryBatcher.maxParallelRecipientSends,
          (target) => _sendHistoryToTarget(config, target, history, logPath),
        );
    return EmailDeliveryBatcher.summarizeDeliveryResults(results);
  }

  Future<DeliverySendSummary> _sendWarningToTargets(
    EmailConfig config,
    List<EmailNotificationTarget> targets,
    String databaseName,
    String warningMessage,
  ) async {
    final enabledTargets = targets.where((target) => target.enabled).toList();
    final results =
        await EmailDeliveryBatcher.runInBatches<
          EmailNotificationTarget,
          RecipientDeliveryResult
        >(
          enabledTargets,
          EmailDeliveryBatcher.maxParallelRecipientSends,
          (target) => _sendWarningToTarget(
            config: config,
            target: target,
            databaseName: databaseName,
            warningMessage: warningMessage,
          ),
        );
    return EmailDeliveryBatcher.summarizeDeliveryResults(results);
  }

  Future<RecipientDeliveryResult> _sendHistoryToTarget(
    EmailConfig config,
    EmailNotificationTarget target,
    BackupHistory history,
    String? logPath,
  ) async {
    final eventType = NotificationEventPolicy.eventTypeFor(history.status);
    final shouldNotify = NotificationEventPolicy.shouldNotifyTarget(
      target,
      history.status,
    );
    if (!shouldNotify) {
      final result = RecipientDeliveryResult.skipped(
        recipientEmail: target.recipientEmail,
        reason: NotificationEventPolicy.disabledRuleReason(history.status),
      );
      await _auditWriter.saveBackupDeliveryAuditLog(
        historyId: history.id,
        configId: config.id,
        target: target,
        eventType: eventType,
        result: result,
      );
      return result;
    }

    final targetConfig = config.copyWith(recipients: [target.recipientEmail]);
    final rd.Result<bool> sendResult;
    switch (history.status) {
      case BackupStatus.success:
        sendResult = await _emailService.sendBackupSuccessNotification(
          config: targetConfig,
          history: history,
          logPath: logPath,
        );
      case BackupStatus.error:
        sendResult = await _emailService.sendBackupErrorNotification(
          config: targetConfig,
          history: history,
          logPath: logPath,
        );
      case BackupStatus.warning:
        final warningMessage = (history.errorMessage?.isNotEmpty ?? false)
            ? history.errorMessage!
            : 'Backup concluído com aviso (sem detalhes).';
        sendResult = await _emailService.sendBackupWarningNotification(
          config: targetConfig,
          databaseName: history.databaseName,
          warningMessage: warningMessage,
          logPath: logPath,
        );
      case BackupStatus.running:
        final result = RecipientDeliveryResult.skipped(
          recipientEmail: target.recipientEmail,
          reason: 'Status running não dispara notificação',
        );
        await _auditWriter.saveBackupDeliveryAuditLog(
          historyId: history.id,
          configId: config.id,
          target: target,
          eventType: eventType,
          result: result,
        );
        return result;
    }

    final result = RecipientDeliveryResult.fromEmailSendResult(
      sendResult,
      recipientEmail: target.recipientEmail,
    );
    await _auditWriter.saveBackupDeliveryAuditLog(
      historyId: history.id,
      configId: config.id,
      target: target,
      eventType: eventType,
      result: result,
    );
    return result;
  }

  Future<RecipientDeliveryResult> _sendWarningToTarget({
    required EmailConfig config,
    required EmailNotificationTarget target,
    required String databaseName,
    required String warningMessage,
  }) async {
    if (!target.notifyOnWarning) {
      final result = RecipientDeliveryResult.skipped(
        recipientEmail: target.recipientEmail,
        reason: 'Regra de aviso desabilitada para destinatário',
      );
      await _auditWriter.saveBackupDeliveryAuditLog(
        configId: config.id,
        target: target,
        eventType: 'backup_warning',
        result: result,
      );
      return result;
    }

    final targetConfig = config.copyWith(recipients: [target.recipientEmail]);
    final sendResult = await _emailService.sendBackupWarningNotification(
      config: targetConfig,
      databaseName: databaseName,
      warningMessage: warningMessage,
    );
    final result = RecipientDeliveryResult.fromEmailSendResult(
      sendResult,
      recipientEmail: target.recipientEmail,
    );
    await _auditWriter.saveBackupDeliveryAuditLog(
      configId: config.id,
      target: target,
      eventType: 'backup_warning',
      result: result,
    );
    return result;
  }

  Future<String?> _exportLogsForBackup(String backupHistoryId) async {
    try {
      final logsResult = await _backupLogRepository.getByBackupHistory(
        backupHistoryId,
      );

      return logsResult.fold((logs) async {
        if (logs.isEmpty) return null;

        final buffer = StringBuffer();
        buffer.writeln('Logs do Backup - ${DateTime.now()}');
        buffer.writeln('=' * 50);
        buffer.writeln();

        for (final log in logs) {
          buffer.writeln(
            '[${log.createdAt}] [${log.level.name.toUpperCase()}] ${log.message}',
          );
          if (log.details != null) {
            buffer.writeln('  Detalhes: ${log.details}');
          }
        }

        final tempDir = await Directory.systemTemp.createTemp('backup_logs_');
        final logFile = File('${tempDir.path}/backup_log.txt');
        await logFile.writeAsString(buffer.toString());

        return logFile.path;
      }, (failure) => null);
    } on Object catch (e) {
      LoggerService.warning('Erro ao exportar logs: $e');
      return null;
    }
  }
}
