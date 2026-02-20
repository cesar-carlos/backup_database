import 'dart:io';

import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/domain/services/i_email_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class NotificationService implements INotificationService {
  NotificationService({
    required IEmailConfigRepository emailConfigRepository,
    required IEmailNotificationTargetRepository
    emailNotificationTargetRepository,
    required IBackupLogRepository backupLogRepository,
    required IEmailService emailService,
    required ILicenseValidationService licenseValidationService,
  }) : _emailConfigRepository = emailConfigRepository,
       _emailNotificationTargetRepository = emailNotificationTargetRepository,
       _backupLogRepository = backupLogRepository,
       _emailService = emailService,
       _licenseValidationService = licenseValidationService;

  final IEmailConfigRepository _emailConfigRepository;
  final IEmailNotificationTargetRepository _emailNotificationTargetRepository;
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

  Future<rd.Result<bool>> testEmailConfiguration(
    EmailConfig config,
  ) async {
    const subject = 'Teste de Configuracao - Backup Database';
    final body =
        '''
Este e um e-mail de teste do Sistema de Backup.

Se voce recebeu este e-mail, a configuracao esta funcionando corretamente.

Data/Hora do teste: ${DateTime.now()}
''';

    return _emailService.sendEmail(
      config: config,
      subject: subject,
      body: body,
    );
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
          'Notificacao por email bloqueada - licenca nao possui permissao',
        );
      }
      return allowed;
    } on Object catch (e) {
      LoggerService.warning('Erro ao verificar licenca para notificacao: $e');
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
    var sentAny = false;
    Exception? firstFailure;

    for (final target in targets.where((t) => t.enabled)) {
      if (!target.notifyOnWarning) {
        continue;
      }

      final targetConfig = config.copyWith(
        recipients: [target.recipientEmail],
        notifyOnWarning: true,
      );

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
      if (!target.notifyOnSuccess) {
        return Future.value(const rd.Success(false));
      }
      return _emailService.sendBackupSuccessNotification(
        config: config.copyWith(
          recipients: [target.recipientEmail],
          notifyOnSuccess: true,
        ),
        history: history,
        logPath: logPath,
      );
    }

    if (history.status == BackupStatus.error) {
      if (!target.notifyOnError) {
        return Future.value(const rd.Success(false));
      }
      return _emailService.sendBackupErrorNotification(
        config: config.copyWith(
          recipients: [target.recipientEmail],
          notifyOnError: true,
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
}
