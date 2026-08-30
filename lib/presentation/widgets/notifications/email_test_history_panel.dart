import 'package:backup_database/application/providers/notification_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/notifications/email_test_history_panel/email_test_history_entry_card.dart';
import 'package:backup_database/presentation/widgets/notifications/email_test_history_panel/email_test_history_format.dart';
import 'package:backup_database/presentation/widgets/notifications/email_test_history_panel/email_test_history_metric_grid.dart';
import 'package:backup_database/presentation/widgets/notifications/email_test_history_panel/email_test_history_metric_tile.dart';
import 'package:fluent_ui/fluent_ui.dart';

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

  @override
  Widget build(BuildContext context) {
    final configNameById = <String, String>{
      for (final config in configs) config.id: config.configName,
    };
    final sortedHistory = [...history]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final latestEntry = sortedHistory.isEmpty ? null : sortedHistory.first;
    final failureCount = sortedHistory
        .where((entry) => !entry.isSuccess)
        .length;
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
          EmailTestHistoryMetricGrid(
            children: [
              EmailTestHistoryMetricTile(
                label: appLocaleString(
                  context,
                  'Último teste',
                  'Latest test',
                ),
                value: latestEntry == null
                    ? appLocaleString(context, 'Sem dados', 'No data')
                    : EmailTestHistoryFormat.formatCreatedAt(
                        context,
                        latestEntry.createdAt,
                      ),
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
              EmailTestHistoryMetricTile(
                label: appLocaleString(context, 'Falhas', 'Failures'),
                value: '$failureCount',
                caption: appLocaleString(
                  context,
                  'Quantidade de testes com erro no período atual.',
                  'Number of failed tests in the current period.',
                ),
              ),
              EmailTestHistoryMetricTile(
                label: appLocaleString(context, 'Sucessos', 'Successes'),
                value: '$successCount',
                caption: appLocaleString(
                  context,
                  'Tentativas concluídas sem erro.',
                  'Attempts completed without errors.',
                ),
              ),
              EmailTestHistoryMetricTile(
                label: appLocaleString(
                  context,
                  'Destinatário mais testado',
                  'Most-tested recipient',
                ),
                value: EmailTestHistoryFormat.mostTestedRecipient(
                  context,
                  sortedHistory,
                ),
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
                  for (
                    var index = 0;
                    index < sortedHistory.length;
                    index++
                  ) ...[
                    EmailTestHistoryEntryCard(
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
