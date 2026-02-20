import 'package:backup_database/application/providers/connection_log_provider.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/connection_log.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ConnectionLogsList extends StatefulWidget {
  const ConnectionLogsList({super.key});

  @override
  State<ConnectionLogsList> createState() => _ConnectionLogsListState();
}

class _ConnectionLogsListState extends State<ConnectionLogsList> {
  String _t(String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConnectionLogProvider>().loadLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionLogProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.logs.isEmpty) {
          return const Center(child: ProgressRing());
        }
        if (provider.error != null) {
          return AppCard(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    FluentIcons.error,
                    size: 64,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    provider.error!,
                    style: FluentTheme.of(context).typography.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Button(
                    onPressed: () => provider.loadLogs(),
                    child: Text(_t('Tentar novamente', 'Try again')),
                  ),
                ],
              ),
            ),
          );
        }
        if (provider.logs.isEmpty) {
          return AppCard(
            child: EmptyState(
              icon: FluentIcons.history,
              message: _t('Nenhum registro de conexao', 'No connection logs'),
              actionLabel: _t('Atualizar', 'Refresh'),
              onAction: () => provider.loadLogs(),
            ),
          );
        }
        return _ConnectionLogsContent(provider: provider);
      },
    );
  }
}

class _ConnectionLogsContent extends StatelessWidget {
  const _ConnectionLogsContent({required this.provider});

  final ConnectionLogProvider provider;
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

  String _t(BuildContext context, String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  String _filterLabel(BuildContext context, ConnectionLogFilter filter) {
    switch (filter) {
      case ConnectionLogFilter.all:
        return _t(context, 'Todos', 'All');
      case ConnectionLogFilter.success:
        return _t(context, 'Sucesso', 'Success');
      case ConnectionLogFilter.failed:
        return _t(context, 'Falha', 'Failure');
    }
  }

  String _serverId(ConnectionLog log) {
    final value = log.serverId?.trim();
    if (value == null || value.isEmpty) return '-';
    return value;
  }

  String _errorMessage(ConnectionLog log) {
    final value = log.errorMessage?.trim();
    if (value == null || value.isEmpty) return '-';
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final filterOptions = [
      ConnectionLogFilter.all,
      ConnectionLogFilter.success,
      ConnectionLogFilter.failed,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 200,
              child: ComboBox<ConnectionLogFilter>(
                value: provider.filter,
                isExpanded: true,
                placeholder: Text(_t(context, 'Filtrar', 'Filter')),
                items: filterOptions
                    .map(
                      (f) => ComboBoxItem<ConnectionLogFilter>(
                        value: f,
                        child: Text(_filterLabel(context, f)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) provider.setFilter(value);
                },
              ),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed: provider.loadLogs,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.refresh, size: 16),
                  const SizedBox(width: 6),
                  Text(_t(context, 'Atualizar', 'Refresh')),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: AppCard(
            child: AppDataGrid<ConnectionLog>(
              minWidth: 1100,
              columns: [
                AppDataGridColumn<ConnectionLog>(
                  label: _t(context, 'Host do cliente', 'Client host'),
                  width: const FlexColumnWidth(2),
                  cellBuilder: (context, row) => Text(
                    row.clientHost,
                    style: FluentTheme.of(context).typography.bodyStrong,
                  ),
                ),
                AppDataGridColumn<ConnectionLog>(
                  label: 'Server ID',
                  width: const FlexColumnWidth(1.4),
                  cellBuilder: (context, row) => SelectableText(_serverId(row)),
                ),
                AppDataGridColumn<ConnectionLog>(
                  label: _t(context, 'Data/Hora', 'Date/Time'),
                  width: const FlexColumnWidth(1.5),
                  cellBuilder: (context, row) => Text(
                    _dateFormat.format(row.timestamp),
                  ),
                ),
                AppDataGridColumn<ConnectionLog>(
                  label: _t(context, 'Status', 'Status'),
                  width: const FlexColumnWidth(1.1),
                  cellAlignment: Alignment.center,
                  headerAlignment: Alignment.center,
                  cellBuilder: (context, row) =>
                      _StatusChip(success: row.success),
                ),
                AppDataGridColumn<ConnectionLog>(
                  label: _t(context, 'Mensagem de erro', 'Error message'),
                  width: const FlexColumnWidth(3),
                  cellBuilder: (context, row) {
                    final message = _errorMessage(row);
                    if (message == '-') {
                      return const Text('-');
                    }

                    return Tooltip(
                      message: message,
                      child: Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentTheme.of(
                          context,
                        ).typography.body?.copyWith(color: AppColors.error),
                      ),
                    );
                  },
                ),
              ],
              rows: provider.logs,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.success});

  final bool success;

  String _t(BuildContext context, String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  Widget build(BuildContext context) {
    final color = success ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            success ? FluentIcons.check_mark : FluentIcons.cancel,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            success
                ? _t(context, 'Sucesso', 'Success')
                : _t(context, 'Falha', 'Failure'),
            style: FluentTheme.of(context).typography.caption?.copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
