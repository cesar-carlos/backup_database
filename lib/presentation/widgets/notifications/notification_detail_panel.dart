import 'package:backup_database/application/providers/notification_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/notifications/email_test_history_panel.dart';
import 'package:fluent_ui/fluent_ui.dart';

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
            'Selecione uma configuracao SMTP para visualizar os detalhes.',
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
          canManage: canManage,
          isTesting: isTestingSelectedConfig,
          onEdit: () => onEditConfig(config),
          onDelete: () => onDeleteConfig(config),
          onAddTarget: onAddTarget,
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
    required this.canManage,
    required this.isTesting,
    required this.onEdit,
    required this.onDelete,
    required this.onAddTarget,
    required this.onToggleEnabled,
    required this.onTest,
  });

  final EmailConfig config;
  final bool canManage;
  final bool isTesting;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddTarget;
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

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final defaultRecipient = config.recipients.isEmpty
        ? appLocaleString(context, 'Nao definido', 'Not set')
        : config.recipients.first;

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
                        'Resumo da configuracao',
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
                      '${config.username} • ${config.smtpServer}:${config.smtpPort}',
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
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryFactTile(
                label: appLocaleString(context, 'Servidor', 'Server'),
                value: config.smtpServer,
                caption: '${appLocaleString(context, 'Porta', 'Port')}: ${config.smtpPort}',
              ),
              _SummaryFactTile(
                label: appLocaleString(context, 'Conta SMTP', 'SMTP account'),
                value: config.username,
                caption: appLocaleString(
                  context,
                  'Usada para autenticacao e envio.',
                  'Used for authentication and delivery.',
                ),
              ),
              _SummaryFactTile(
                label: appLocaleString(
                  context,
                  'Destinatario padrao de teste',
                  'Default test recipient',
                ),
                value: defaultRecipient,
                caption: appLocaleString(
                  context,
                  'Preenchido no dialog para testes rapidos.',
                  'Pre-filled in the dialog for quick tests.',
                ),
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
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
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
                          Text(appLocaleString(context, 'Testando...', 'Testing...')),
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
                onPressed: canManage ? onAddTarget : null,
                child: Text(
                  appLocaleString(
                    context,
                    'Novo destinatario',
                    'New recipient',
                  ),
                ),
              ),
              Button(
                onPressed: canManage ? onEdit : null,
                child: Text(appLocaleString(context, 'Editar', 'Edit')),
              ),
              Button(
                onPressed: canManage ? onDelete : null,
                child: Text(appLocaleString(context, 'Excluir', 'Delete')),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(appLocaleString(context, 'Ativa', 'Active')),
                  const SizedBox(width: 8),
                  ToggleSwitch(
                    checked: config.enabled,
                    onChanged: canManage ? onToggleEnabled : null,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
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
                        'Destinatarios',
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
                        'Defina quem recebe notificacoes de sucesso, erro e aviso para esta configuracao.',
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
                    'Novo destinatario',
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
                'Nenhum destinatario cadastrado para ${config.configName}.',
                'No recipients registered for ${config.configName}.',
              ),
              actionLabel: appLocaleString(
                context,
                'Novo destinatario',
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
    return AppStatusChip(
      label: label,
      tone: enabled ? tone : AppStatusChipTone.neutral,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final resources = theme.resources;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  target.recipientEmail,
                  style: theme.typography.bodyStrong,
                ),
              ),
              const SizedBox(width: 12),
              AppStatusChip(
                label: target.enabled
                    ? appLocaleString(context, 'Ativo', 'Active')
                    : appLocaleString(context, 'Inativo', 'Inactive'),
                tone: target.enabled
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
          const SizedBox(height: 12),
          Row(
            children: [
              ToggleSwitch(
                checked: target.enabled,
                onChanged: canManage ? onToggleEnabled : null,
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
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
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
