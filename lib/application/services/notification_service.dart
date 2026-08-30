import 'package:backup_database/application/services/notification/backup_notification_dispatcher.dart';
import 'package:backup_database/application/services/notification/email_configuration_tester.dart';
import 'package:backup_database/application/services/notification/notification_audit_writer.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/domain/repositories/i_email_test_audit_repository.dart';
import 'package:backup_database/domain/services/i_email_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class NotificationService implements INotificationService {
  NotificationService({
    required this._emailConfigRepository,
    required IEmailNotificationTargetRepository
    emailNotificationTargetRepository,
    required IEmailTestAuditRepository emailTestAuditRepository,
    required IBackupLogRepository backupLogRepository,
    required this._emailService,
    required this._licenseValidationService,
    this._metricsCollector,
  }) {
    final auditWriter = NotificationAuditWriter(
      backupLogRepository: backupLogRepository,
      emailTestAuditRepository: emailTestAuditRepository,
    );
    _dispatcher = BackupNotificationDispatcher(
      targetRepository: emailNotificationTargetRepository,
      emailService: _emailService,
      backupLogRepository: backupLogRepository,
      auditWriter: auditWriter,
    );
    _emailConfigurationTester = EmailConfigurationTester(
      emailService: _emailService,
      auditWriter: auditWriter,
    );
  }

  final IEmailConfigRepository _emailConfigRepository;
  final IEmailService _emailService;
  final ILicenseValidationService _licenseValidationService;
  final IMetricsCollector? _metricsCollector;
  late final BackupNotificationDispatcher _dispatcher;
  late final EmailConfigurationTester _emailConfigurationTester;

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
      (configs) => _dispatcher.sendHistoryWithConfigs(configs, history),
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
      (configs) =>
          _dispatcher.sendWarningWithConfigs(configs, databaseName, message),
      rd.Failure.new,
    );
  }

  @override
  Future<rd.Result<bool>> testEmailConfiguration(
    EmailConfig config,
  ) async {
    final isAllowed = await _isEmailNotificationAllowed();
    if (!isAllowed) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Notificação por e-mail requer licença válida com permissão.',
        ),
      );
    }

    return _emailConfigurationTester.test(config);
  }

  @override
  Future<rd.Result<void>> sendTestEmail(
    String recipient,
    String subject,
  ) async {
    final isAllowed = await _isEmailNotificationAllowed();
    if (!isAllowed) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Notificação por e-mail requer licença válida com permissão.',
        ),
      );
    }

    final configResult = await _emailConfigRepository.get();

    return configResult.fold((config) async {
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

      return result.fold((success) => const rd.Success(()), rd.Failure.new);
    }, rd.Failure.new);
  }

  Future<bool> _isEmailNotificationAllowed() async {
    try {
      final hasEmailNotification = await _licenseValidationService
          .isFeatureAllowed(LicenseFeatures.emailNotification);

      final allowed = hasEmailNotification.getOrElse((_) => false);
      if (!allowed) {
        _metricsCollector?.incrementCounter(
          ObservabilityMetrics.emailNotificationSkippedLicenseTotal,
        );
        LoggerService.info(
          'Notificação por email bloqueada - licença não possui permissão',
        );
      }
      return allowed;
    } on Object catch (e) {
      LoggerService.warning('Erro ao verificar licença para notificação: $e');
      return false;
    }
  }
}
