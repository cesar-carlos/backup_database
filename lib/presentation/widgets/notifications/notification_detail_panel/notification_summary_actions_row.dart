import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — test, edit, enable and overflow actions for a config.
class NotificationSummaryActionsRow extends StatelessWidget {
  const NotificationSummaryActionsRow({
    required this.canManage,
    required this.isTesting,
    required this.isEnabled,
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
    super.key,
  });

  final bool canManage;
  final bool isTesting;
  final bool isEnabled;
  final VoidCallback onTest;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final statusBlock = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isEnabled
                  ? appLocaleString(
                      context,
                      'Configuração ativa',
                      'Configuration active',
                    )
                  : appLocaleString(
                      context,
                      'Configuração inativa',
                      'Configuration inactive',
                    ),
              style: theme.typography.caption,
            ),
            const SizedBox(width: 8),
            ToggleSwitch(
              checked: isEnabled,
              onChanged: canManage ? onToggleEnabled : null,
            ),
            const SizedBox(width: 4),
            DropDownButton(
              disabled: !canManage,
              leading: const Icon(FluentIcons.more, size: 14),
              title: Text(appLocaleString(context, 'Mais', 'More')),
              items: [
                MenuFlyoutItem(
                  leading: const Icon(FluentIcons.delete),
                  text: Text(appLocaleString(context, 'Excluir', 'Delete')),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        );

        final actionButtons = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: onTest,
              child: isTesting
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: ProgressRing(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          appLocaleString(
                            context,
                            'Testando...',
                            'Testing...',
                          ),
                        ),
                      ],
                    )
                  : Text(
                      appLocaleString(
                        context,
                        'Testar SMTP',
                        'Test SMTP',
                      ),
                    ),
            ),
            Button(
              onPressed: canManage ? onEdit : null,
              child: Text(appLocaleString(context, 'Editar', 'Edit')),
            ),
          ],
        );

        if (constraints.maxWidth >= 760) {
          return Row(
            children: [
              Expanded(child: actionButtons),
              const SizedBox(width: 12),
              statusBlock,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            actionButtons,
            const SizedBox(height: 12),
            statusBlock,
          ],
        );
      },
    );
  }
}
