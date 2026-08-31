import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/notifications/notification_detail_panel/notification_event_chip.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — recipient e-mail, event chips and management actions.
class NotificationRecipientListItem extends StatelessWidget {
  const NotificationRecipientListItem({
    required this.target,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
    super.key,
  });

  final EmailNotificationTarget target;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final outline = context.colors.outline;

    final statusText = target.enabled
        ? appLocaleString(context, 'Ativo', 'Active')
        : appLocaleString(context, 'Inativo', 'Inactive');

    final leftContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          target.recipientEmail,
          style: theme.typography.bodyStrong,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            NotificationEventChip(
              label: appLocaleString(context, 'Sucesso', 'Success'),
              enabled: target.notifyOnSuccess,
              tone: AppStatusChipTone.success,
              onTap: canManage ? onEdit : null,
            ),
            NotificationEventChip(
              label: appLocaleString(context, 'Erro', 'Error'),
              enabled: target.notifyOnError,
              tone: AppStatusChipTone.danger,
              onTap: canManage ? onEdit : null,
            ),
            NotificationEventChip(
              label: appLocaleString(context, 'Aviso', 'Warning'),
              enabled: target.notifyOnWarning,
              tone: AppStatusChipTone.warning,
              onTap: canManage ? onEdit : null,
            ),
          ],
        ),
      ],
    );

    Widget managementColumn(bool alignEnd) {
      return Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(statusText, style: theme.typography.caption),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToggleSwitch(
                checked: target.enabled,
                onChanged: canManage ? onToggleEnabled : null,
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: appLocaleString(context, 'Editar', 'Edit'),
                child: IconButton(
                  icon: const Icon(FluentIcons.edit),
                  onPressed: canManage ? onEdit : null,
                ),
              ),
              Tooltip(
                message: appLocaleString(context, 'Excluir', 'Delete'),
                child: IconButton(
                  icon: const Icon(FluentIcons.delete),
                  onPressed: canManage ? onDelete : null,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: outline.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: outline.withValues(alpha: 0.22)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= AppBreakpoints.compact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: leftContent),
                const SizedBox(width: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 200),
                  child: managementColumn(true),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leftContent,
              const SizedBox(height: 12),
              managementColumn(false),
            ],
          );
        },
      ),
    );
  }
}
