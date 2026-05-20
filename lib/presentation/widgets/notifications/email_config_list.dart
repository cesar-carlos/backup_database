import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class EmailConfigList extends StatefulWidget {
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
  State<EmailConfigList> createState() => _EmailConfigListState();
}

class _EmailConfigListState extends State<EmailConfigList> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EmailConfig> _filteredConfigs() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.configs;
    }

    return widget.configs.where((config) {
      final haystack = [
        config.configName,
        config.smtpServer,
        config.username,
        config.fromEmail,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final filteredConfigs = _filteredConfigs();

    if (widget.isLoading) {
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
              'Configurações SMTP',
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
              'Escolha a configuração que será revisada no painel ao lado.',
              'Choose the configuration to inspect in the detail panel.',
            ),
            style: theme.typography.caption,
          ),
          const SizedBox(height: 16),
          TextBox(
            controller: _searchController,
            placeholder: appLocaleString(
              context,
              'Buscar por nome, servidor ou conta SMTP',
              'Search by name, server, or SMTP account',
            ),
            suffix: _searchController.text.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(FluentIcons.search, size: 14),
                  )
                : IconButton(
                    icon: const Icon(FluentIcons.clear, size: 12),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          if (widget.configs.isEmpty)
            EmptyState(
              icon: FluentIcons.mail,
              message: appLocaleString(
                context,
                'Nenhuma configuração de e-mail cadastrada',
                'No e-mail configuration registered',
              ),
              actionLabel: appLocaleString(
                context,
                'Nova configuração',
                'New configuration',
              ),
              onAction: widget.canManage ? widget.onCreate : null,
            )
          else if (filteredConfigs.isEmpty)
            EmptyState(
              icon: FluentIcons.filter,
              message: appLocaleString(
                context,
                'Nenhuma configuração corresponde ao filtro atual.',
                'No configuration matches the current filter.',
              ),
            )
          else
            Column(
              children: [
                for (var index = 0; index < filteredConfigs.length; index++) ...[
                  _EmailConfigListItem(
                    config: filteredConfigs[index],
                    isSelected:
                        filteredConfigs[index].id == widget.selectedConfigId,
                    isUpdating:
                        widget.updatingConfigIds.contains(filteredConfigs[index].id),
                    canManage: widget.canManage,
                    onSelect: () => widget.onSelect(filteredConfigs[index]),
                    onEdit: () => widget.onEdit(filteredConfigs[index]),
                    onDelete: () => widget.onDelete(filteredConfigs[index]),
                    onToggleEnabled: (value) =>
                        widget.onToggleEnabled(filteredConfigs[index], value),
                  ),
                  if (index < filteredConfigs.length - 1)
                    const SizedBox(height: 12),
                ],
              ],
            ),
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
        return appLocaleString(context, 'Senha SMTP', 'SMTP password');
      case SmtpAuthMode.oauthGoogle:
        return 'Google OAuth2';
      case SmtpAuthMode.oauthMicrosoft:
        return 'Microsoft OAuth2';
    }
  }

  String _recipientsLabel(BuildContext context) {
    final count = config.recipients.length;
    if (appLocaleIsPortuguese(Localizations.localeOf(context))) {
      return count == 1 ? '1 destinatário' : '$count destinatários';
    }
    return count == 1 ? '1 recipient' : '$count recipients';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final resources = theme.resources;
    final borderColor = isSelected
        ? theme.accentColor.withValues(alpha: 0.55)
        : resources.cardStrokeColorDefault.withValues(alpha: 0.85);
    final backgroundColor = isSelected
        ? theme.accentColor.withValues(alpha: 0.14)
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 4,
              height: 96,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isSelected ? theme.accentColor : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Expanded(
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
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  config.configName,
                                  style: theme.typography.bodyStrong,
                                ),
                                if (isSelected)
                                  AppStatusChip(
                                    label: appLocaleString(
                                      context,
                                      'Selecionada',
                                      'Selected',
                                    ),
                                    tone: AppStatusChipTone.info,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${config.smtpServer}:${config.smtpPort}',
                              style: theme.typography.body,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              config.username,
                              style: theme.typography.caption,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      AppStatusChip(
                        label: config.enabled
                            ? appLocaleString(context, 'Ativa', 'Active')
                            : appLocaleString(context, 'Inativa', 'Inactive'),
                        tone: config.enabled
                            ? AppStatusChipTone.success
                            : AppStatusChipTone.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppStatusChip(
                        label: _authModeLabel(context),
                        tone: AppStatusChipTone.info,
                      ),
                      AppStatusChip(
                        label: config.useSsl ? 'SSL' : 'STARTTLS',
                        tone: AppStatusChipTone.warning,
                      ),
                      AppStatusChip(label: _recipientsLabel(context)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        appLocaleString(context, 'Ativa', 'Active'),
                        style: theme.typography.caption,
                      ),
                      const SizedBox(width: 8),
                      ToggleSwitch(
                        checked: config.enabled,
                        onChanged:
                            canManage && !isUpdating ? onToggleEnabled : null,
                      ),
                      if (isUpdating) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(strokeWidth: 2),
                        ),
                      ],
                      const Spacer(),
                      Tooltip(
                        message: appLocaleString(context, 'Editar', 'Edit'),
                        child: IconButton(
                          icon: const Icon(FluentIcons.edit),
                          onPressed: canManage ? onEdit : null,
                        ),
                      ),
                      DropDownButton(
                        disabled: !canManage,
                        leading: const Icon(FluentIcons.more, size: 14),
                        title: Text(
                          appLocaleString(context, 'Mais', 'More'),
                        ),
                        items: [
                          MenuFlyoutItem(
                            leading: const Icon(FluentIcons.delete),
                            text: Text(
                              appLocaleString(context, 'Excluir', 'Delete'),
                            ),
                            onPressed: onDelete,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
