import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class EmailConfigList extends StatelessWidget {
  const EmailConfigList({
    required this.configs,
    required this.selectedConfigId,
    required this.canManage,
    required this.isLoading,
    required this.updatingConfigIds,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onSelect,
    required this.onToggleEnabled,
    super.key,
  });

  final List<EmailConfig> configs;
  final String? selectedConfigId;
  final bool canManage;
  final bool isLoading;
  final Set<String> updatingConfigIds;
  final VoidCallback onCreate;
  final ValueChanged<EmailConfig> onEdit;
  final ValueChanged<EmailConfig> onDelete;
  final ValueChanged<EmailConfig> onSelect;
  final void Function(EmailConfig config, bool enabled) onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final captionStyle = theme.typography.caption;

    if (isLoading) {
      return const AppCard(
        child: SizedBox(
          height: 180,
          child: Center(child: ProgressRing()),
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appLocaleString(
              context,
              'Configuracoes SMTP',
              'SMTP configurations',
            ),
            style: theme.typography.subtitle?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            appLocaleString(
              context,
              'Escolha uma configuracao para revisar destinatarios, testar o envio e consultar o historico.',
              'Choose a configuration to review recipients, test delivery, and inspect history.',
            ),
            style: captionStyle,
          ),
          const SizedBox(height: 16),
          if (configs.isEmpty)
            EmptyState(
              icon: FluentIcons.mail,
              message: appLocaleString(
                context,
                'Nenhuma configuracao de e-mail cadastrada',
                'No e-mail configuration registered',
              ),
              actionLabel: appLocaleString(
                context,
                'Nova configuracao',
                'New configuration',
              ),
              onAction: canManage ? onCreate : null,
            )
          else ...[
            for (var index = 0; index < configs.length; index++) ...[
              _EmailConfigListItem(
                config: configs[index],
                isSelected: configs[index].id == selectedConfigId,
                isUpdating: updatingConfigIds.contains(configs[index].id),
                canManage: canManage,
                onSelect: () => onSelect(configs[index]),
                onEdit: () => onEdit(configs[index]),
                onDelete: () => onDelete(configs[index]),
                onToggleEnabled: (value) => onToggleEnabled(configs[index], value),
              ),
              if (index < configs.length - 1) const SizedBox(height: 12),
            ],
            if (canManage) ...[
              const SizedBox(height: 12),
              Button(
                onPressed: onCreate,
                child: Text(
                  appLocaleString(
                    context,
                    'Nova configuracao',
                    'New configuration',
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _EmailConfigListItem extends StatelessWidget {
  const _EmailConfigListItem({
    required this.config,
    required this.isSelected,
    required this.isUpdating,
    required this.canManage,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
  });

  final EmailConfig config;
  final bool isSelected;
  final bool isUpdating;
  final bool canManage;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleEnabled;

  String _authModeLabel(BuildContext context) {
    switch (config.authMode) {
      case SmtpAuthMode.password:
        return appLocaleString(context, 'Senha', 'Password');
      case SmtpAuthMode.oauthGoogle:
        return 'Google OAuth2';
      case SmtpAuthMode.oauthMicrosoft:
        return 'Microsoft OAuth2';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final resources = theme.resources;
    final borderColor = isSelected
        ? theme.accentColor.withValues(alpha: 0.35)
        : resources.cardStrokeColorDefault.withValues(alpha: 0.85);
    final backgroundColor = isSelected
        ? theme.accentColor.withValues(alpha: 0.10)
        : resources.cardStrokeColorDefault.withValues(alpha: 0.08);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.configName,
                        style: theme.typography.bodyStrong,
                      ),
                      const SizedBox(height: 4),
                      Text('${config.smtpServer}:${config.smtpPort}'),
                      const SizedBox(height: 2),
                      Text(
                        config.username,
                        style: theme.typography.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    AppStatusChip(
                      label: config.enabled
                          ? appLocaleString(context, 'Ativa', 'Active')
                          : appLocaleString(context, 'Inativa', 'Inactive'),
                      tone: config.enabled
                          ? AppStatusChipTone.success
                          : AppStatusChipTone.neutral,
                    ),
                    AppStatusChip(
                      label: _authModeLabel(context),
                      tone: AppStatusChipTone.info,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ToggleSwitch(
                  checked: config.enabled,
                  onChanged: canManage && !isUpdating ? onToggleEnabled : null,
                ),
                const SizedBox(width: 8),
                if (isUpdating)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: ProgressRing(strokeWidth: 2),
                  ),
                const Spacer(),
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
        ),
      ),
    );
  }
}
