import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/notifications/notification_detail_panel/notification_recipient_list_item.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — recipient list for a selected SMTP configuration.
class NotificationRecipientsSection extends StatelessWidget {
  const NotificationRecipientsSection({
    required this.config,
    required this.targets,
    required this.canManage,
    required this.onAddTarget,
    required this.onEditTarget,
    required this.onDeleteTarget,
    required this.onToggleTargetEnabled,
    super.key,
  });

  final EmailConfig config;
  final List<EmailNotificationTarget> targets;
  final bool canManage;
  final VoidCallback onAddTarget;
  final ValueChanged<EmailNotificationTarget> onEditTarget;
  final ValueChanged<EmailNotificationTarget> onDeleteTarget;
  final void Function(EmailNotificationTarget target, bool enabled)
  onToggleTargetEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appLocaleString(
                        context,
                        'Destinatários',
                        'Recipients',
                      ),
                      style: theme.typography.subtitle?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      appLocaleString(
                        context,
                        'Defina quem recebe notificações de sucesso, erro e aviso para esta configuração.',
                        'Choose who receives success, error, and warning notifications for this configuration.',
                      ),
                      style: theme.typography.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Button(
                onPressed: canManage ? onAddTarget : null,
                child: Text(
                  appLocaleString(
                    context,
                    'Novo destinatário',
                    'New recipient',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (targets.isEmpty)
            EmptyState(
              icon: FluentIcons.group,
              message: appLocaleString(
                context,
                'Nenhum destinatário cadastrado para ${config.configName}.',
                'No recipients registered for ${config.configName}.',
              ),
              actionLabel: appLocaleString(
                context,
                'Novo destinatário',
                'New recipient',
              ),
              onAction: canManage ? onAddTarget : null,
            )
          else
            Column(
              children: [
                for (var index = 0; index < targets.length; index++) ...[
                  NotificationRecipientListItem(
                    target: targets[index],
                    canManage: canManage,
                    onEdit: () => onEditTarget(targets[index]),
                    onDelete: () => onDeleteTarget(targets[index]),
                    onToggleEnabled: (value) =>
                        onToggleTargetEnabled(targets[index], value),
                  ),
                  if (index < targets.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
