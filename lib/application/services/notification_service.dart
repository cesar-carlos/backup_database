import 'dart:io';

import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:backup_database/infrastructure/external/email/email_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class NotificationService implements INotificationService {
  NotificationService({
    required IEmailConfigRepository emailConfigRepository,
    required IBackupLogRepository backupLogRepository,
    required EmailService emailService,
  }) : _emailConfigRepository = emailConfigRepository,
       _backupLogRepository = backupLogRepository,
       _emailService = emailService;
  final IEmailConfigRepository _emailConfigRepository;
  final IBackupLogRepository _backupLogRepository;
  final EmailService _emailService;

  @override
  Future<rd.Result<bool>> notifyBackupComplete(
    BackupHistory history,
  ) async {
    try {
      final licenseValidationService = service_locator
          .getIt<ILicenseValidationService>();
      final hasEmailNotification = await licenseValidationService
          .isFeatureAllowed(LicenseFeatures.emailNotification);

      if (!hasEmailNotification.getOrElse((_) => false)) {
        LoggerService.info(
          'Notificação por email bloqueada - licença não possui permissão',
        );
        return const rd.Success(false);
      }
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao verificar licença para notificação: $e',
      );
    }

    final configResult = await _emailConfigRepository.get();

    return configResult.fold(
      (config) async {
        if (!config.enabled) {
          return const rd.Success(false);
        }

        String? logPath;
        if (config.attachLog) {
          logPath = await _exportLogsForBackup(history.id);
        }

        if (history.status == BackupStatus.success) {
          return _emailService.sendBackupSuccessNotification(
            config: config,
            history: history,
            logPath: logPath,
          );
        } else if (history.status == BackupStatus.error) {
          return _emailService.sendBackupErrorNotification(
            config: config,
            history: history,
            logPath: logPath,
          );
        }

        return const rd.Success(false);
      },
      rd.Failure.new,
    );
  }

  @override
  Future<rd.Result<bool>> sendWarning({
    required String databaseName,
    required String message,
  }) async {
    final configResult = await _emailConfigRepository.get();

    return configResult.fold(
      (config) async {
        if (!config.enabled) {
          return const rd.Success(false);
        }

        return _emailService.sendBackupWarningNotification(
          config: config,
          databaseName: databaseName,
          warningMessage: message,
        );
      },
      rd.Failure.new,
    );
  }

  Future<rd.Result<bool>> testEmailConfiguration(
    EmailConfig config,
  ) async {
    const subject = '🔧 Teste de Configuração - Backup Database';
    final body =
        '''
Este é um e-mail de teste do Sistema de Backup.

Se você recebeu este e-mail, a configuração está funcionando corretamente.

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
Este é um e-mail de teste do Sistema de Backup.

Data/Hora do teste: ${DateTime.now()}
''';

        final result = await _emailService.sendEmail(
          config: config,
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
              '[${log.createdAt}] [${log.level.name.toUpperCase()}] '
              '${log.message}',
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
}
