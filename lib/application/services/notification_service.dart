import 'dart:io';

import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/domain/repositories/i_email_test_audit_repository.dart';
import 'package:backup_database/domain/services/i_email_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class NotificationService implements INotificationService {
  NotificationService({
    required IEmailConfigRepository emailConfigRepository,
    required IEmailNotificationTargetRepository
    emailNotificationTargetRepository,
    required IEmailTestAuditRepository emailTestAuditRepository,
    required IBackupLogRepository backupLogRepository,
    required IEmailService emailService,
    required ILicenseValidationService licenseValidationService,
  }) : _emailConfigRepository = emailConfigRepository,
       _emailNotificationTargetRepository = emailNotificationTargetRepository,
       _emailTestAuditRepository = emailTestAuditRepository,
       _backupLogRepository = backupLogRepository,
       _emailService = emailService,
       _licenseValidationService = licenseValidationService;

  final IEmailConfigRepository _emailConfigRepository;
  final IEmailNotificationTargetRepository _emailNotificationTargetRepository;
  final IEmailTestAuditRepository _emailTestAuditRepository;
  final IBackupLogRepository _backupLogRepository;
  final IEmailService _emailService;
  final ILicenseValidationService _licenseValidationService;

  @override
  Future<rd.Result<bool>> notifyBackupComplete(
    BackupHistory history,
  ) async {
    final isAllowed = await _isEmailNotificationAllowed();
    if (!isAllowed) {
      return const rd.Success(false);
    }

    final configResult = await _emailConfigRepository.getAll();
    return configResult.fold(
      (configs) => _sendHistoryWithConfigs(configs, history),
      rd.Failure.new,
    );
  }

  @override
  Future<rd.Result<bool>> sendWarning({
    required String databaseName,
    required String message,
  }) async {
    final isAllowed = await _isEmailNotificationAllowed();
    if (!isAllowed) {
      return const rd.Success(false);
    }

    final configResult = await _emailConfigRepository.getAll();
    return configResult.fold(
      (configs) => _sendWarningWithConfigs(configs, databaseName, message),
      rd.Failure.new,
    );
  }

  @override
  Future<rd.Result<bool>> testEmailConfiguration(
    EmailConfig config,
  ) async {
    final correlationId = _buildTestCorrelationId(config.id);
    final destinationRecipient = config.recipients
        .map((email) => email.trim())
        .where((email) => email.isNotEmpty)
        .firstOrNull;
    if (destinationRecipient == null || !destinationRecipient.contains('@')) {
      const failure = ValidationFailure(
        message:
            'Informe um e-mail de destino válido para testar a configuração',
      );
      await _saveEmailTestAudit(
        config: config,
        correlationId: correlationId,
        recipientEmail: '',
        senderEmail: config.fromEmail.trim().isNotEmpty
            ? config.fromEmail.trim()
            : config.username.trim(),
        failure: failure,
      );
      return const rd.Failure(failure);
    }

    final senderEmail = config.fromEmail.trim().isNotEmpty
        ? config.fromEmail.trim()
        : config.username.trim();
    if (senderEmail.isEmpty || !senderEmail.contains('@')) {
      const failure = ValidationFailure(
        message:
            'Informe um e-mail SMTP válido para realizar o teste de conexão',
      );
      await _saveEmailTestAudit(
        config: config,
        correlationId: correlationId,
        recipientEmail: destinationRecipient,
        senderEmail: senderEmail,
        failure: failure,
      );
      return const rd.Failure(failure);
    }

    LoggerService.info(
      '[NotificationService] Iniciando teste SMTP | '
      'correlationId=$correlationId '
      'configId=${config.id} '
      'server=${config.smtpServer}:${config.smtpPort} '
      'to=$destinationRecipient',
    );

    final subject = '[SMTP-TEST:$correlationId] ${config.configName}';
    final body =
        '''
Esta é uma mensagem de teste da configuração SMTP do Backup Database.

Objetivo:
- Validar servidor, credenciais e entrega para o destinatario configurado.

Configuração testada:
- Nome: ${config.configName}
- Servidor SMTP: ${config.smtpServer}
- Porta: ${config.smtpPort}
- Usuário SMTP: ${config.username}
- Destinatario de teste: $destinationRecipient
- Correlation ID: $correlationId

Se você recebeu este e-mail, a configuração está funcionando corretamente.

Data/Hora do teste: ${DateTime.now()}
''';

    final sendResult = await _emailService.sendEmail(
      config: config.copyWith(
        recipients: [destinationRecipient],
        fromEmail: senderEmail,
      ),
      subject: subject,
      body: body,
    );

    sendResult.fold(
      (_) async {
        LoggerService.info(
          '[NotificationService] Teste SMTP aceito | '
          'correlationId=$correlationId '
          'to=$destinationRecipient',
        );
        await _saveEmailTestAudit(
          config: config,
          correlationId: correlationId,
          recipientEmail: destinationRecipient,
          senderEmail: senderEmail,
        );
      },
      (failure) async {
        LoggerService.warning(
          '[NotificationService] Teste SMTP falhou | '
          'correlationId=$correlationId '
          'to=$destinationRecipient '
          'erro=$failure',
        );
        await _saveEmailTestAudit(
          config: config,
          correlationId: correlationId,
          recipientEmail: destinationRecipient,
          senderEmail: senderEmail,
          failure: failure,
        );
      },
    );

    return sendResult;
  }

  @override
  Future<rd.Result<void>> sendTestEmail(
    String recipient,
    String subject,
  ) async {
    final configResult = await _emailConfigRepository.get();

    return configResult.fold(
      (config) async {
        final body =
            '''
Este e um e-mail de teste do Sistema de Backup.

Data/Hora do teste: ${DateTime.now()}
''';

        final result = await _emailService.sendEmail(
          config: config.copyWith(recipients: [recipient]),
          subject: subject,
          body: body,
        );

        return result.fold(
          (success) => const rd.Success(()),
          rd.Failure.new,
        );
      },
      rd.Failure.new,
    );
  }

  Future<bool> _isEmailNotificationAllowed() async {
    try {
      final hasEmailNotification = await _licenseValidationService
          .isFeatureAllowed(LicenseFeatures.emailNotification);

      final allowed = hasEmailNotification.getOrElse((_) => false);
      if (!allowed) {
        LoggerService.info(
          'Notificação por email bloqueada - licença não possui permissão',
        );
      }
      return allowed;
    } on Object catch (e) {
      LoggerService.warning('Erro ao verificar licença para notificação: $e');
      return true;
    }
  }

  Future<rd.Result<bool>> _sendHistoryWithConfigs(
    List<EmailConfig> configs,
    BackupHistory history,
  ) async {
    var sentAny = false;
    Exception? firstFailure;

    for (final config in configs.where((cfg) => cfg.enabled)) {
      String? logPath;
      if (config.attachLog) {
        logPath = await _exportLogsForBackup(history.id);
      }

      final targetResult = await _emailNotificationTargetRepository
          .getByConfigId(
            config.id,
          );

      rd.Result<bool> sendResult;
      if (targetResult.isSuccess()) {
        final targets = targetResult.getOrElse((_) => const []);
        if (targets.isEmpty) {
          LoggerService.info(
            'Configuracao ${config.id} sem destinatarios ativos para envio.',
          );
          sendResult = const rd.Success(false);
        } else {
          sendResult = await _sendHistoryToTargets(
            config,
            targets,
            history,
            logPath,
          );
        }
      } else {
        final failure =
            targetResult.exceptionOrNull() ??
            Exception('Falha desconhecida ao carregar destinatarios');
        LoggerService.warning(
          'Falha ao buscar targets da configuracao ${config.id}: $failure',
        );
        sendResult = rd.Failure(_toException(failure));
      }

      sendResult.fold(
        (sent) {
          if (sent) {
            sentAny = true;
          }
        },
        (failure) {
          firstFailure ??= _toException(failure);
        },
      );
    }

    if (sentAny) {
      return const rd.Success(true);
    }
    if (firstFailure != null) {
      return rd.Failure(firstFailure!);
    }
    return const rd.Success(false);
  }

  Future<rd.Result<bool>> _sendWarningWithConfigs(
    List<EmailConfig> configs,
    String databaseName,
    String message,
  ) async {
    var sentAny = false;
    Exception? firstFailure;

    for (final config in configs.where((cfg) => cfg.enabled)) {
      final targetResult = await _emailNotificationTargetRepository
          .getByConfigId(
            config.id,
          );

      rd.Result<bool> sendResult;
      if (targetResult.isSuccess()) {
        final targets = targetResult.getOrElse((_) => const []);
        if (targets.isEmpty) {
          LoggerService.info(
            'Configuracao ${config.id} sem destinatarios ativos para envio de aviso.',
          );
          sendResult = const rd.Success(false);
        } else {
          sendResult = await _sendWarningToTargets(
            config,
            targets,
            databaseName,
            message,
          );
        }
      } else {
        final failure =
            targetResult.exceptionOrNull() ??
            Exception('Falha desconhecida ao carregar destinatarios');
        LoggerService.warning(
          'Falha ao buscar targets da configuracao ${config.id}: $failure',
        );
        sendResult = rd.Failure(_toException(failure));
      }

      sendResult.fold(
        (sent) {
          if (sent) {
            sentAny = true;
          }
        },
        (failure) {
          firstFailure ??= _toException(failure);
        },
      );
    }

    if (sentAny) {
      return const rd.Success(true);
    }
    if (firstFailure != null) {
      return rd.Failure(firstFailure!);
    }
    return const rd.Success(false);
  }

  Future<rd.Result<bool>> _sendHistoryToTargets(
    EmailConfig config,
    List<EmailNotificationTarget> targets,
    BackupHistory history,
    String? logPath,
  ) async {
    var sentAny = false;
    Exception? firstFailure;

    for (final target in targets.where((t) => t.enabled)) {
      final result = await _sendHistoryToTarget(
        config,
        target,
        history,
        logPath,
      );
      result.fold(
        (sent) {
          if (sent) {
            sentAny = true;
          }
        },
        (failure) {
          firstFailure ??= _toException(failure);
        },
      );
    }

    if (sentAny) {
      return const rd.Success(true);
    }
    if (firstFailure != null) {
      return rd.Failure(firstFailure!);
    }
    return const rd.Success(false);
  }

  Future<rd.Result<bool>> _sendWarningToTargets(
    EmailConfig config,
    List<EmailNotificationTarget> targets,
    String databaseName,
    String warningMessage,
  ) async {
    if (!config.notifyOnWarning) {
      return const rd.Success(false);
    }

    var sentAny = false;
    Exception? firstFailure;

    for (final target in targets.where((t) => t.enabled)) {
      final targetConfig = config.copyWith(recipients: [target.recipientEmail]);

      final result = await _emailService.sendBackupWarningNotification(
        config: targetConfig,
        databaseName: databaseName,
        warningMessage: warningMessage,
      );

      result.fold(
        (sent) {
          if (sent) {
            sentAny = true;
          }
        },
        (failure) {
          firstFailure ??= _toException(failure);
        },
      );
    }

    if (sentAny) {
      return const rd.Success(true);
    }
    if (firstFailure != null) {
      return rd.Failure(firstFailure!);
    }
    return const rd.Success(false);
  }

  Future<rd.Result<bool>> _sendHistoryToTarget(
    EmailConfig config,
    EmailNotificationTarget target,
    BackupHistory history,
    String? logPath,
  ) {
    if (history.status == BackupStatus.success) {
      if (!config.notifyOnSuccess) {
        return Future.value(const rd.Success(false));
      }
      return _emailService.sendBackupSuccessNotification(
        config: config.copyWith(
          recipients: [target.recipientEmail],
        ),
        history: history,
        logPath: logPath,
      );
    }

    if (history.status == BackupStatus.error) {
      if (!config.notifyOnError) {
        return Future.value(const rd.Success(false));
      }
      return _emailService.sendBackupErrorNotification(
        config: config.copyWith(
          recipients: [target.recipientEmail],
        ),
        history: history,
        logPath: logPath,
      );
    }

    return Future.value(const rd.Success(false));
  }

  Future<String?> _exportLogsForBackup(String backupHistoryId) async {
    try {
      final logsResult = await _backupLogRepository.getByBackupHistory(
        backupHistoryId,
      );

      return logsResult.fold(
        (logs) async {
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
        },
        (failure) => null,
      );
    } on Object catch (e) {
      LoggerService.warning('Erro ao exportar logs: $e');
      return null;
    }
  }

  Exception _toException(Object failure) {
    if (failure is Exception) {
      return failure;
    }
    return Exception(failure.toString());
  }

  String _buildTestCorrelationId(String configId) {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final normalizedId = configId.replaceAll('-', '');
    final suffix = normalizedId.length <= 8
        ? normalizedId
        : normalizedId.substring(normalizedId.length - 8);
    return '$timestamp-$suffix';
  }

  Future<void> _saveEmailTestAudit({
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
      errorType: _classifyTestFailureType(failure),
      errorMessage: failure?.toString(),
    );

    final result = await _emailTestAuditRepository.create(audit);
    result.fold(
      (_) => null,
      (saveFailure) => LoggerService.warning(
        '[NotificationService] Falha ao persistir auditoria SMTP: $saveFailure',
      ),
    );
  }

  String? _classifyTestFailureType(Object? failure) {
    if (failure == null) {
      return null;
    }

    final text = failure.toString().toLowerCase();
    if (text.contains('autenticacao') ||
        text.contains('authentication') ||
        text.contains('535')) {
      return 'authentication';
    }
    if (text.contains('timeout') ||
        text.contains('socket') ||
        text.contains('conectar')) {
      return 'connectivity';
    }
    if (text.contains('rejeitou') || text.contains('rejected')) {
      return 'smtp_rejection';
    }
    if (text.contains('invalido') ||
        text.contains('validation') ||
        text.contains('destino')) {
      return 'validation';
    }
    return 'unknown';
  }
}
