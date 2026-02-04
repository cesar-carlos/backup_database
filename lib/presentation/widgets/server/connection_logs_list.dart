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
                    child: const Text('Tentar Novamente'),
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
              message: 'Nenhum registro de conexão',
              actionLabel: 'Atualizar',
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

  static const String _filterAll = 'Todos';
  static const String _filterSuccess = 'Sucesso';
  static const String _filterFailed = 'Falha';

  String _filterLabel(ConnectionLogFilter filter) {
    switch (filter) {
      case ConnectionLogFilter.all:
        return _filterAll;
      case ConnectionLogFilter.success:
        return _filterSuccess;
      case ConnectionLogFilter.failed:
        return _filterFailed;
    }
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
            ComboBox<ConnectionLogFilter>(
              value: provider.filter,
              items: filterOptions
                  .map(
                    (f) => ComboBoxItem<ConnectionLogFilter>(
                      value: f,
                      child: Text(_filterLabel(f)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) provider.setFilter(value);
              },
            ),
            const SizedBox(width: 8),
            CommandBar(
              primaryItems: [
                CommandBarButton(
                  icon: const Icon(FluentIcons.refresh),
                  onPressed: provider.loadLogs,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: provider.logs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
              _ConnectionLogRow(log: provider.logs[index]),
          ),
        ),
      ],
    );
  }
}

class _ConnectionLogRow extends StatelessWidget {
  const _ConnectionLogRow({required this.log});

  final ConnectionLog log;

  static final DateFormat _dateFormat =
      DateFormat('dd/MM/yyyy HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        log.clientHost,
                        style: FluentTheme.of(context).typography.bodyStrong,
                      ),
                      if (log.serverId != null && log.serverId!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Server ID: ${log.serverId}',
                          style: FluentTheme.of(context).typography.caption,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _dateFormat.format(log.timestamp),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  if (log.errorMessage != null &&
                      log.errorMessage!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      log.errorMessage!,
                      style: FluentTheme.of(context).typography.body?.copyWith(
                            color: AppColors.error,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _StatusChip(success: log.success),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.success});

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
            success ? 'Sucesso' : 'Falha',
            style: FluentTheme.of(context).typography.caption?.copyWith(
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}
