import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';

class EmailNotificationProfile {
  const EmailNotificationProfile({
    required this.config,
    required this.targets,
  });

  final EmailConfig config;
  final List<EmailNotificationTarget> targets;

  bool get hasEnabledTargets => targets.any((target) => target.enabled);
}
