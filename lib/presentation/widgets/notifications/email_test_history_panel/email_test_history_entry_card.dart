import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/notifications/email_test_history_panel/email_test_history_format.dart';
import 'package:backup_database/presentation/widgets/notifications/email_test_history_panel/email_test_history_metric_grid.dart';
import 'package:backup_database/presentation/widgets/notifications/email_test_history_panel/email_test_history_metric_tile.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// **Molecule** — expandable SMTP test audit entry with copyable details.
class EmailTestHistoryEntryCard extends StatelessWidget {
  const EmailTestHistoryEntryCard({
    required this.audit,
    required this.configName,
    super.key,
  });

  final EmailTestAudit audit;
  final String configName;

  Future<void> _copyValue(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) {
      return;
    }
    await FluentInfoBarFeedback.showSuccess(
      context,
      message: appLocaleString(
        context,
        'Valor copiado para a área de transferência.',
        'Value copied to the clipboard.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final resources = theme.resources;
    final summaryText = audit.isSuccess
        ? appLocaleString(
            context,
            'Envio validado com sucesso para o destinatário.',
            'Delivery validated successfully for the recipient.',
          )
        : (audit.errorType ??
              appLocaleString(
                context,
                'Falha sem tipo informado.',
                'Failure without a reported type.',
              ));

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: resources.cardStrokeColorDefault.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: resources.cardStrokeColorDefault.withValues(alpha: 0.85),
        ),
      ),
      child: Expander(
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final trailing = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppStatusChip(
                      label: audit.isSuccess
                          ? appLocaleString(context, 'Sucesso', 'Success')
                          : appLocaleString(context, 'Falha', 'Failure'),
                      tone: audit.isSuccess
                          ? AppStatusChipTone.success
                          : AppStatusChipTone.danger,
                    ),
                    AppStatusChip(
                      label: EmailTestHistoryFormat.pluralizedAttemptLabel(
                        context,
                        audit.attempts,
                      ),
                    ),
                  ],
                );

                final leading = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audit.recipientEmail,
                      style: theme.typography.bodyStrong,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$configName | ${EmailTestHistoryFormat.formatCreatedAt(context, audit.createdAt)}',
                      style: theme.typography.caption,
                    ),
                  ],
                );

                if (constraints.maxWidth >= 760) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: leading),
                      const SizedBox(width: 12),
                      trailing,
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading,
                    const SizedBox(height: 8),
                    trailing,
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              summaryText,
              style: theme.typography.caption,
            ),
          ],
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmailTestHistoryMetricGrid(
              children: [
                EmailTestHistoryMetricTile(
                  label: appLocaleString(
                    context,
                    'Configuração',
                    'Configuration',
                  ),
                  value: configName,
                  caption: appLocaleString(
                    context,
                    'Origem lógica usada no teste.',
                    'Logical source used in the test.',
                  ),
                ),
                EmailTestHistoryMetricTile(
                  label: appLocaleString(
                    context,
                    'Remetente',
                    'Sender',
                  ),
                  value: audit.senderEmail,
                  caption: appLocaleString(
                    context,
                    'Conta usada no envio.',
                    'Account used for delivery.',
                  ),
                ),
                EmailTestHistoryMetricTile(
                  label: appLocaleString(
                    context,
                    'Endpoint SMTP',
                    'SMTP endpoint',
                  ),
                  value: '${audit.smtpServer}:${audit.smtpPort}',
                  caption: appLocaleString(
                    context,
                    'Servidor e porta observados na auditoria.',
                    'Server and port observed in the audit.',
                  ),
                ),
                EmailTestHistoryMetricTile(
                  label: appLocaleString(
                    context,
                    'Duração',
                    'Duration',
                  ),
                  value: audit.durationMs == null
                      ? appLocaleString(
                          context,
                          'Não informada',
                          'Not available',
                        )
                      : '${audit.durationMs} ms',
                  caption: appLocaleString(
                    context,
                    'Tempo registrado para a tentativa.',
                    'Recorded time for the attempt.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  appLocaleString(
                    context,
                    'ID de correlação',
                    'Correlation ID',
                  ),
                  style: theme.typography.caption,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(FluentIcons.copy, size: 14),
                  onPressed: () => _copyValue(context, audit.correlationId),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              audit.correlationId,
              style: theme.typography.body,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  appLocaleString(
                    context,
                    'Destinatário',
                    'Recipient',
                  ),
                  style: theme.typography.caption,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(FluentIcons.copy, size: 14),
                  onPressed: () => _copyValue(context, audit.recipientEmail),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              audit.recipientEmail,
              style: theme.typography.body,
            ),
            if (audit.errorMessage != null &&
                audit.errorMessage!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    appLocaleString(
                      context,
                      'Mensagem técnica',
                      'Technical message',
                    ),
                    style: theme.typography.caption,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(FluentIcons.copy, size: 14),
                    onPressed: () =>
                        _copyValue(context, audit.errorMessage!.trim()),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(
                audit.errorMessage!.trim(),
                style: theme.typography.body,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
