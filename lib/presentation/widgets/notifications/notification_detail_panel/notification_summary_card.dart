import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/notifications/notification_detail_panel/notification_responsive_fact_grid.dart';
import 'package:backup_database/presentation/widgets/notifications/notification_detail_panel/notification_summary_actions_row.dart';
import 'package:backup_database/presentation/widgets/notifications/notification_detail_panel/notification_summary_fact_tile.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

/// **Organism** — selected SMTP configuration summary, facts and actions.
class NotificationSummaryCard extends StatelessWidget {
  const NotificationSummaryCard({
    required this.config,
    required this.targets,
    required this.testHistory,
    required this.canManage,
    required this.isTesting,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
    required this.onTest,
    super.key,
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
        : ([
            ...testHistory,
          ]..sort((a, b) => b.createdAt.compareTo(a.createdAt))).first;
    final latestFailure =
        testHistory.where((entry) => !entry.isSuccess).toList()
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
          NotificationResponsiveFactGrid(
            children: [
              NotificationSummaryFactTile(
                label: appLocaleString(context, 'Servidor SMTP', 'SMTP server'),
                value: config.smtpServer,
                caption:
                    '${appLocaleString(context, 'Porta', 'Port')}: ${config.smtpPort}',
              ),
              NotificationSummaryFactTile(
                label: appLocaleString(context, 'Conta SMTP', 'SMTP account'),
                value: config.username,
                caption: appLocaleString(
                  context,
                  'Usada para autenticação e envio.',
                  'Used for authentication and delivery.',
                ),
              ),
              NotificationSummaryFactTile(
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
              NotificationSummaryFactTile(
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
              NotificationSummaryFactTile(
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
              NotificationSummaryFactTile(
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
              NotificationSummaryFactTile(
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
          NotificationSummaryActionsRow(
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
