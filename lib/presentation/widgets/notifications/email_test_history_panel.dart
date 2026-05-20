import 'package:backup_database/application/providers/notification_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class EmailTestHistoryPanel extends StatelessWidget {
  const EmailTestHistoryPanel({
    required this.history,
    required this.configs,
    required this.isLoading,
    required this.error,
    required this.selectedConfigId,
    required this.period,
    required this.onConfigChanged,
    required this.onPeriodChanged,
    required this.onRefresh,
    super.key,
  });

  final List<EmailTestAudit> history;
  final List<EmailConfig> configs;
  final bool isLoading;
  final String? error;
  final String? selectedConfigId;
  final NotificationHistoryPeriod period;
  final ValueChanged<String?> onConfigChanged;
  final ValueChanged<NotificationHistoryPeriod> onPeriodChanged;
  final VoidCallback onRefresh;

  static String _formatCreatedAt(BuildContext context, DateTime date) {
    if (appLocaleIsPortuguese(Localizations.localeOf(context))) {
      return DateFormat('dd/MM/yyyy HH:mm:ss', 'pt_BR').format(date);
    }
    return DateFormat('M/d/yyyy h:mm:ss a', 'en_US').format(date);
  }

  static String _pluralizedAttemptLabel(BuildContext context, int count) {
    if (appLocaleIsPortuguese(Localizations.localeOf(context))) {
      return count == 1 ? '1 tentativa' : '$count tentativas';
    }
    return count == 1 ? '1 attempt' : '$count attempts';
  }

  static String _mostTestedRecipient(
    BuildContext context,
    List<EmailTestAudit> history,
  ) {
    if (history.isEmpty) {
      return appLocaleString(context, 'Não disponível', 'Unavailable');
    }

    final counters = <String, int>{};
    for (final entry in history) {
      counters.update(
        entry.recipientEmail,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    final winner = counters.entries.reduce(
      (best, current) => current.value > best.value ? current : best,
    );
    return winner.key;
  }

  @override
  Widget build(BuildContext context) {
    final configNameById = <String, String>{
      for (final config in configs) config.id: config.configName,
    };
    final sortedHistory = [...history]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final latestEntry = sortedHistory.isEmpty ? null : sortedHistory.first;
    final failureCount = sortedHistory.where((entry) => !entry.isSuccess).length;
    final successCount = sortedHistory.length - failureCount;
    final theme = FluentTheme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appLocaleString(
              context,
              'Histórico de testes SMTP',
              'SMTP test history',
            ),
            style: theme.typography.subtitle?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            appLocaleString(
              context,
              'Use os filtros para revisar tentativas recentes, falhas e destinatários mais testados.',
              'Use the filters to inspect recent attempts, failures, and most-tested recipients.',
            ),
            style: theme.typography.caption,
          ),
          const SizedBox(height: 16),
          _ResponsiveMetricGrid(
            children: [
              _HistoryMetricTile(
                label: appLocaleString(
                  context,
                  'Último teste',
                  'Latest test',
                ),
                value: latestEntry == null
                    ? appLocaleString(context, 'Sem dados', 'No data')
                    : _formatCreatedAt(context, latestEntry.createdAt),
                caption: latestEntry == null
                    ? appLocaleString(
                        context,
                        'Nenhuma execução registrada no filtro atual.',
                        'No executions recorded for the current filter.',
                      )
                    : appLocaleString(
                        context,
                        'Última tentativa observada no histórico filtrado.',
                        'Latest attempt observed in the filtered history.',
                      ),
              ),
              _HistoryMetricTile(
                label: appLocaleString(context, 'Falhas', 'Failures'),
                value: '$failureCount',
                caption: appLocaleString(
                  context,
                  'Quantidade de testes com erro no período atual.',
                  'Number of failed tests in the current period.',
                ),
              ),
              _HistoryMetricTile(
                label: appLocaleString(context, 'Sucessos', 'Successes'),
                value: '$successCount',
                caption: appLocaleString(
                  context,
                  'Tentativas concluídas sem erro.',
                  'Attempts completed without errors.',
                ),
              ),
              _HistoryMetricTile(
                label: appLocaleString(
                  context,
                  'Destinatário mais testado',
                  'Most-tested recipient',
                ),
                value: _mostTestedRecipient(context, sortedHistory),
                caption: appLocaleString(
                  context,
                  'Ajuda a identificar o alvo operacional mais recorrente.',
                  'Helps identify the most common operational target.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: SizedBox(
                  height: 34,
                  child: AppDropdown<String?>(
                    label: appLocaleString(
                      context,
                      'Configuração',
                      'Configuration',
                    ),
                    compact: true,
                    value: selectedConfigId,
                    items: [
                      ComboBoxItem<String?>(
                        child: Text(
                          appLocaleString(
                            context,
                            'Todas as configurações',
                            'All configurations',
                          ),
                        ),
                      ),
                      ...configs.map(
                        (config) => ComboBoxItem<String?>(
                          value: config.id,
                          child: Text(config.configName),
                        ),
                      ),
                    ],
                    onChanged: onConfigChanged,
                    placeholder: Text(
                      appLocaleString(
                        context,
                        'Todas as configurações',
                        'All configurations',
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: SizedBox(
                  height: 34,
                  child: AppDropdown<NotificationHistoryPeriod>(
                    label: appLocaleString(context, 'Período', 'Period'),
                    compact: true,
                    value: period,
                    items: [
                      ComboBoxItem(
                        value: NotificationHistoryPeriod.last24Hours,
                        child: Text(
                          appLocaleString(
                            context,
                            'Últimas 24h',
                            'Last 24 hours',
                          ),
                        ),
                      ),
                      ComboBoxItem(
                        value: NotificationHistoryPeriod.last7Days,
                        child: Text(
                          appLocaleString(
                            context,
                            'Últimos 7 dias',
                            'Last 7 days',
                          ),
                        ),
                      ),
                      ComboBoxItem(
                        value: NotificationHistoryPeriod.last30Days,
                        child: Text(
                          appLocaleString(
                            context,
                            'Últimos 30 dias',
                            'Last 30 days',
                          ),
                        ),
                      ),
                      ComboBoxItem(
                        value: NotificationHistoryPeriod.all,
                        child: Text(
                          appLocaleString(
                            context,
                            'Todo o período',
                            'All time',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onPeriodChanged(value);
                      }
                    },
                    placeholder: Text(
                      appLocaleString(
                        context,
                        'Últimos 7 dias',
                        'Last 7 days',
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 32,
                child: Button(
                  onPressed: onRefresh,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.refresh, size: 16),
                      const SizedBox(width: 6),
                      Text(appLocaleString(context, 'Atualizar', 'Refresh')),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const SizedBox(
              height: 120,
              child: Center(child: ProgressRing()),
            )
          else if (error != null)
            InfoBar(
              severity: InfoBarSeverity.error,
              title: Text(
                appLocaleString(
                  context,
                  'Erro ao carregar histórico',
                  'Error loading history',
                ),
              ),
              content: Text(error!),
            )
          else if (sortedHistory.isEmpty)
            EmptyState(
              icon: FluentIcons.history,
              message: appLocaleString(
                context,
                'Nenhum teste SMTP encontrado para o filtro atual.',
                'No SMTP tests found for the current filter.',
              ),
            )
          else
            Expander(
              header: Text(
                appLocaleString(
                  context,
                  'Ver histórico detalhado',
                  'View detailed history',
                ),
              ),
              content: Column(
                children: [
                  for (var index = 0; index < sortedHistory.length; index++) ...[
                    _HistoryEntryCard(
                      audit: sortedHistory[index],
                      configName:
                          configNameById[sortedHistory[index].configId] ??
                          sortedHistory[index].configId,
                    ),
                    if (index < sortedHistory.length - 1)
                      const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ResponsiveMetricGrid extends StatelessWidget {
  const _ResponsiveMetricGrid({required this.children});

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

class _HistoryMetricTile extends StatelessWidget {
  const _HistoryMetricTile({
    required this.label,
    required this.value,
    required this.caption,
  });

  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
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
          Text(label, style: theme.typography.caption),
          const SizedBox(height: 4),
          Text(value, style: theme.typography.subtitle),
          const SizedBox(height: 4),
          Text(caption, style: theme.typography.caption),
        ],
      ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({
    required this.audit,
    required this.configName,
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
                      label: EmailTestHistoryPanel._pluralizedAttemptLabel(
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
                      '$configName | ${EmailTestHistoryPanel._formatCreatedAt(context, audit.createdAt)}',
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
            _ResponsiveMetricGrid(
              children: [
                _HistoryMetricTile(
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
                _HistoryMetricTile(
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
                _HistoryMetricTile(
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
                _HistoryMetricTile(
                  label: appLocaleString(
                    context,
                    'Duração',
                    'Duration',
                  ),
                  value: audit.durationMs == null
                      ? appLocaleString(context, 'Não informada', 'Not available')
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
