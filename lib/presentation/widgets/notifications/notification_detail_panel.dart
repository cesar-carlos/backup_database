import 'package:backup_database/application/providers/notification_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/notifications/email_test_history_panel.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

class NotificationDetailPanel extends StatelessWidget {
  const NotificationDetailPanel({
    required this.selectedConfig,
    required this.configs,
    required this.targets,
    required this.testHistory,
    required this.historyError,
    required this.isHistoryLoading,
    required this.historyPeriod,
    required this.historyConfigIdFilter,
    required this.canManage,
    required this.isTestingSelectedConfig,
    required this.onEditConfig,
    required this.onDeleteConfig,
    required this.onAddTarget,
    required this.onEditTarget,
    required this.onDeleteTarget,
    required this.onToggleConfigEnabled,
    required this.onToggleTargetEnabled,
    required this.onTestConfig,
    required this.onHistoryConfigChanged,
    required this.onHistoryPeriodChanged,
    required this.onRefreshHistory,
    super.key,
  });

  final EmailConfig? selectedConfig;
  final List<EmailConfig> configs;
  final List<EmailNotificationTarget> targets;
  final List<EmailTestAudit> testHistory;
  final String? historyError;
  final bool isHistoryLoading;
  final NotificationHistoryPeriod historyPeriod;
  final String? historyConfigIdFilter;
  final bool canManage;
  final bool isTestingSelectedConfig;
  final ValueChanged<EmailConfig> onEditConfig;
  final ValueChanged<EmailConfig> onDeleteConfig;
  final VoidCallback onAddTarget;
  final ValueChanged<EmailNotificationTarget> onEditTarget;
  final ValueChanged<EmailNotificationTarget> onDeleteTarget;
  final void Function(EmailConfig config, bool enabled) onToggleConfigEnabled;
  final void Function(EmailNotificationTarget target, bool enabled)
  onToggleTargetEnabled;
  final VoidCallback onTestConfig;
  final ValueChanged<String?> onHistoryConfigChanged;
  final ValueChanged<NotificationHistoryPeriod> onHistoryPeriodChanged;
  final VoidCallback onRefreshHistory;

  @override
  Widget build(BuildContext context) {
    final config = selectedConfig;
    if (config == null) {
      return AppCard(
        child: EmptyState(
          icon: FluentIcons.mail,
          message: appLocaleString(
            context,
            'Selecione uma configuração SMTP para visualizar os detalhes.',
            'Select an SMTP configuration to view details.',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NotificationSummaryCard(
          config: config,
          targets: targets,
          testHistory: testHistory,
          canManage: canManage,
          isTesting: isTestingSelectedConfig,
          onEdit: () => onEditConfig(config),
          onDelete: () => onDeleteConfig(config),
          onToggleEnabled: (value) => onToggleConfigEnabled(config, value),
          onTest: onTestConfig,
        ),
        const SizedBox(height: 16),
        _RecipientsSection(
          config: config,
          targets: targets,
          canManage: canManage,
          onAddTarget: onAddTarget,
          onEditTarget: onEditTarget,
          onDeleteTarget: onDeleteTarget,
          onToggleTargetEnabled: onToggleTargetEnabled,
        ),
        const SizedBox(height: 16),
        EmailTestHistoryPanel(
          history: testHistory,
          configs: configs,
          isLoading: isHistoryLoading,
          error: historyError,
          selectedConfigId: historyConfigIdFilter,
          period: historyPeriod,
          onConfigChanged: onHistoryConfigChanged,
          onPeriodChanged: onHistoryPeriodChanged,
          onRefresh: onRefreshHistory,
        ),
      ],
    );
  }
}

class _NotificationSummaryCard extends StatelessWidget {
  const _NotificationSummaryCard({
    required this.config,
    required this.targets,
    required this.testHistory,
    required this.canManage,
    required this.isTesting,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
    required this.onTest,
  });

  final EmailConfig config;
  final List<EmailNotificationTarget> targets;
  final List<EmailTestAudit> testHistory;
  final bool canManage;
  final bool isTesting;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onTest;

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

  String _formatDateTime(BuildContext context, DateTime date) {
    if (appLocaleIsPortuguese(Localizations.localeOf(context))) {
      return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(date);
    }
    return DateFormat('M/d/yyyy h:mm a', 'en_US').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final defaultRecipient = config.recipients.isEmpty
        ? appLocaleString(context, 'Não definido', 'Not set')
        : config.recipients.first;
    final latestTest = testHistory.isEmpty
        ? null
        : ([...testHistory]..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
            .first;
    final latestFailure = testHistory
        .where((entry) => !entry.isSuccess)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final activeRecipients = targets.where((target) => target.enabled).length;
    final lastFailure = latestFailure.isEmpty ? null : latestFailure.first;

    return AppCard(
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
                      appLocaleString(
                        context,
                        'Resumo da configuração',
                        'Configuration summary',
                      ),
                      style: theme.typography.subtitle?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(config.configName, style: theme.typography.title),
                    const SizedBox(height: 4),
                    Text(
                      '${config.username} | ${config.smtpServer}:${config.smtpPort}',
                      style: theme.typography.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
                  AppStatusChip(
                    label: config.useSsl ? 'SSL' : 'STARTTLS',
                    tone: AppStatusChipTone.warning,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (latestTest != null)
            InfoBar(
              severity: latestTest.isSuccess
                  ? InfoBarSeverity.success
                  : InfoBarSeverity.error,
              title: Text(
                latestTest.isSuccess
                    ? appLocaleString(
                        context,
                        'Último teste concluído com sucesso',
                        'Latest test completed successfully',
                      )
                    : appLocaleString(
                        context,
                        'Último teste registrou falha',
                        'Latest test failed',
                      ),
              ),
              content: Text(
                latestTest.isSuccess
                    ? appLocaleString(
                        context,
                        'Tentativa em ${_formatDateTime(context, latestTest.createdAt)} para ${latestTest.recipientEmail}.',
                        'Attempt at ${_formatDateTime(context, latestTest.createdAt)} for ${latestTest.recipientEmail}.',
                      )
                    : (latestTest.errorMessage?.trim().isNotEmpty ?? false)
                        ? latestTest.errorMessage!.trim()
                        : appLocaleString(
                            context,
                            'Revise o histórico para detalhes técnicos.',
                            'Review the history for technical details.',
                          ),
              ),
              isLong: true,
            ),
          if (latestTest != null) const SizedBox(height: 16),
          _ResponsiveFactGrid(
            children: [
              _SummaryFactTile(
                label: appLocaleString(context, 'Servidor SMTP', 'SMTP server'),
                value: config.smtpServer,
                caption:
                    '${appLocaleString(context, 'Porta', 'Port')}: ${config.smtpPort}',
              ),
              _SummaryFactTile(
                label: appLocaleString(context, 'Conta SMTP', 'SMTP account'),
                value: config.username,
                caption: appLocaleString(
                  context,
                  'Usada para autenticação e envio.',
                  'Used for authentication and delivery.',
                ),
              ),
              _SummaryFactTile(
                label: appLocaleString(
                  context,
                  'Último teste',
                  'Latest test',
                ),
                value: latestTest == null
                    ? appLocaleString(context, 'Sem histórico', 'No history')
                    : _formatDateTime(context, latestTest.createdAt),
                caption: latestTest == null
                    ? appLocaleString(
                        context,
                        'Ainda não há auditoria para esta configuração.',
                        'There is no audit for this configuration yet.',
                      )
                    : latestTest.isSuccess
                        ? appLocaleString(
                            context,
                            'Última tentativa concluída sem erro.',
                            'Latest attempt completed without errors.',
                          )
                        : appLocaleString(
                            context,
                            'Última tentativa terminou com falha.',
                            'Latest attempt ended in failure.',
                          ),
              ),
              _SummaryFactTile(
                label: appLocaleString(
                  context,
                  'Destinatários ativos',
                  'Active recipients',
                ),
                value: '$activeRecipients',
                caption: appLocaleString(
                  context,
                  'Recebem notificações no estado atual.',
                  'Receive notifications in the current state.',
                ),
              ),
              _SummaryFactTile(
                label: appLocaleString(
                  context,
                  'Destinatário padrão de teste',
                  'Default test recipient',
                ),
                value: defaultRecipient,
                caption: appLocaleString(
                  context,
                  'Preenchido automaticamente nos testes rápidos.',
                  'Pre-filled automatically in quick tests.',
                ),
              ),
              _SummaryFactTile(
                label: appLocaleString(
                  context,
                  'Última falha',
                  'Latest failure',
                ),
                value: lastFailure == null
                    ? appLocaleString(
                        context,
                        'Nenhuma falha recente',
                        'No recent failure',
                      )
                    : _formatDateTime(context, lastFailure.createdAt),
                caption: lastFailure == null
                    ? appLocaleString(
                        context,
                        'Nenhum erro foi encontrado no filtro atual.',
                        'No error was found in the current filter.',
                      )
                    : (lastFailure.errorType ??
                        appLocaleString(
                          context,
                          'Falha sem tipo informado.',
                          'Failure without a reported type.',
                        )),
              ),
              _SummaryFactTile(
                label: appLocaleString(context, 'Anexos', 'Attachments'),
                value: config.attachLog
                    ? appLocaleString(context, 'Logs ativos', 'Logs enabled')
                    : appLocaleString(context, 'Sem logs', 'No logs'),
                caption: appLocaleString(
                  context,
                  'Controla o envio de detalhamento no e-mail.',
                  'Controls whether detailed logs are attached.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SummaryActionsRow(
            canManage: canManage,
            isTesting: isTesting,
            isEnabled: config.enabled,
            onTest: onTest,
            onEdit: onEdit,
            onDelete: onDelete,
            onToggleEnabled: onToggleEnabled,
          ),
        ],
      ),
    );
  }
}

class _SummaryActionsRow extends StatelessWidget {
  const _SummaryActionsRow({
    required this.canManage,
    required this.isTesting,
    required this.isEnabled,
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
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

class _ResponsiveFactGrid extends StatelessWidget {
  const _ResponsiveFactGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= 1180 => 4,
          >= 720 => 2,
          _ => 1,
        };

        if (columns == 1) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index < children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          final end = (start + columns) > children.length
              ? children.length
              : start + columns;
          final rowChildren = children.sublist(start, end);

          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < rowChildren.length; index++) ...[
                    Expanded(child: rowChildren[index]),
                    if (index < rowChildren.length - 1) const SizedBox(width: 12),
                  ],
                  for (var filler = rowChildren.length; filler < columns; filler++) ...[
                    if (filler > 0) const SizedBox(width: 12),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              rows[index],
              if (index < rows.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _RecipientsSection extends StatelessWidget {
  const _RecipientsSection({
    required this.config,
    required this.targets,
    required this.canManage,
    required this.onAddTarget,
    required this.onEditTarget,
    required this.onDeleteTarget,
    required this.onToggleTargetEnabled,
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
                  _RecipientListItem(
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

class _RecipientListItem extends StatelessWidget {
  const _RecipientListItem({
    required this.target,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
  });

  final EmailNotificationTarget target;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleEnabled;

  Widget _eventChip(
    BuildContext context, {
    required String label,
    required bool enabled,
    required AppStatusChipTone tone,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canManage ? onEdit : null,
      child: AppStatusChip(
        label: label,
        tone: enabled ? tone : AppStatusChipTone.neutral,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final resources = theme.resources;

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
            _eventChip(
              context,
              label: appLocaleString(context, 'Sucesso', 'Success'),
              enabled: target.notifyOnSuccess,
              tone: AppStatusChipTone.success,
            ),
            _eventChip(
              context,
              label: appLocaleString(context, 'Erro', 'Error'),
              enabled: target.notifyOnError,
              tone: AppStatusChipTone.danger,
            ),
            _eventChip(
              context,
              label: appLocaleString(context, 'Aviso', 'Warning'),
              enabled: target.notifyOnWarning,
              tone: AppStatusChipTone.warning,
            ),
          ],
        ),
      ],
    );

    Widget managementColumn(bool alignEnd) {
      return Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
        color: resources.cardStrokeColorDefault.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: resources.cardStrokeColorDefault.withValues(alpha: 0.85),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
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

class _SummaryFactTile extends StatelessWidget {
  const _SummaryFactTile({
    required this.label,
    required this.value,
    required this.caption,
  });

  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final captionStyle = FluentTheme.of(context).typography.caption;
    final borderColor = const Color(0xFF8A8A8A).withValues(alpha: 0.22);
    final backgroundColor = const Color(0xFF8A8A8A).withValues(alpha: 0.08);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: captionStyle),
          const SizedBox(height: 4),
          Text(value, style: FluentTheme.of(context).typography.subtitle),
          const SizedBox(height: 4),
          Text(caption, style: captionStyle),
        ],
      ),
    );
  }
}
