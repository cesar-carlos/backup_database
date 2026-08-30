import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';

abstract final class NotificationEventPolicy {
  static String eventTypeFor(BackupStatus status) => switch (status) {
    BackupStatus.success => 'backup_success',
    BackupStatus.error => 'backup_error',
    BackupStatus.warning => 'backup_warning',
    BackupStatus.running => 'backup_running',
  };

  static bool shouldNotifyTarget(
    EmailNotificationTarget target,
    BackupStatus status,
  ) => switch (status) {
    BackupStatus.success => target.notifyOnSuccess,
    BackupStatus.error => target.notifyOnError,
    BackupStatus.warning => target.notifyOnWarning,
    BackupStatus.running => false,
  };

  static String disabledRuleReason(BackupStatus status) => switch (status) {
    BackupStatus.success => 'Regra de sucesso desabilitada para destinatário',
    BackupStatus.error => 'Regra de erro desabilitada para destinatário',
    BackupStatus.warning => 'Regra de aviso desabilitada para destinatário',
    BackupStatus.running => 'Status running não suporta envio',
  };
}
