import 'package:backup_database/application/providers/notification_provider.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
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

  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Historico de testes SMTP',
                style: FluentTheme.of(context).typography.subtitle?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 220,
                child: ComboBox<String?>(
                  value: selectedConfigId,
                  items: [
                    const ComboBoxItem<String?>(
                      child: Text('Todas configuracoes'),
                    ),
                    ...configs.map(
                      (config) => ComboBoxItem<String?>(
                        value: config.id,
                        child: Text(config.configName),
                      ),
                    ),
                  ],
                  onChanged: onConfigChanged,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
                child: ComboBox<NotificationHistoryPeriod>(
                  value: period,
                  isExpanded: true,
                  items: const [
                    ComboBoxItem(
                      value: NotificationHistoryPeriod.last24Hours,
                      child: Text('Ultimas 24h'),
                    ),
                    ComboBoxItem(
                      value: NotificationHistoryPeriod.last7Days,
                      child: Text('Ultimos 7 dias'),
                    ),
                    ComboBoxItem(
                      value: NotificationHistoryPeriod.last30Days,
                      child: Text('Ultimos 30 dias'),
                    ),
                    ComboBoxItem(
                      value: NotificationHistoryPeriod.all,
                      child: Text('Todo periodo'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      onPeriodChanged(value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: onRefresh,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.refresh, size: 16),
                    SizedBox(width: 6),
                    Text('Atualizar'),
                  ],
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
              title: const Text('Erro ao carregar historico'),
              content: Text(error!),
            )
          else if (history.isEmpty)
            const EmptyState(
              icon: FluentIcons.history,
              message: 'Nenhum teste SMTP encontrado para o filtro atual',
            )
          else
            AppDataGrid<EmailTestAudit>(
              minWidth: 1300,
              columns: [
                AppDataGridColumn<EmailTestAudit>(
                  label: 'Data/Hora',
                  width: const FlexColumnWidth(1.2),
                  cellBuilder: (context, row) => Text(
                    _dateFormat.format(row.createdAt),
                  ),
                ),
                AppDataGridColumn<EmailTestAudit>(
                  label: 'Configuracao',
                  width: const FlexColumnWidth(1.4),
                  cellBuilder: (context, row) => Text(
                    _resolveConfigName(row.configId),
                  ),
                ),
                AppDataGridColumn<EmailTestAudit>(
                  label: 'Destinatario',
                  width: const FlexColumnWidth(1.5),
                  cellBuilder: (context, row) => Text(row.recipientEmail),
                ),
                AppDataGridColumn<EmailTestAudit>(
                  label: 'Status',
                  width: const FlexColumnWidth(0.9),
                  cellBuilder: (context, row) =>
                      _StatusBadge(success: row.isSuccess),
                ),
                AppDataGridColumn<EmailTestAudit>(
                  label: 'Tipo de erro',
                  cellBuilder: (context, row) => Text(row.errorType ?? '-'),
                ),
                AppDataGridColumn<EmailTestAudit>(
                  label: 'Tentativas',
                  width: const FixedColumnWidth(90),
                  cellAlignment: Alignment.center,
                  headerAlignment: Alignment.center,
                  cellBuilder: (context, row) => Text('${row.attempts}'),
                ),
                AppDataGridColumn<EmailTestAudit>(
                  label: 'Correlation ID',
                  width: const FlexColumnWidth(1.6),
                  cellBuilder: (context, row) => SelectableText(
                    row.correlationId,
                    maxLines: 1,
                  ),
                ),
                AppDataGridColumn<EmailTestAudit>(
                  label: 'Mensagem',
                  width: const FlexColumnWidth(2.2),
                  cellBuilder: (context, row) {
                    final message = row.errorMessage?.trim();
                    if (message == null || message.isEmpty) {
                      return const Text('-');
                    }
                    return Tooltip(
                      message: message,
                      child: Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ],
              rows: history,
            ),
        ],
      ),
    );
  }

  String _resolveConfigName(String configId) {
    for (final config in configs) {
      if (config.id == configId) {
        return config.configName;
      }
    }
    return configId;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.success});

  final bool success;

  @override
  Widget build(BuildContext context) {
    final color = success ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        success ? 'Sucesso' : 'Falha',
        style:
            FluentTheme.of(
              context,
            ).typography.caption?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
