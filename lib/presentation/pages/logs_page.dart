import 'package:intl/intl.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';

import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../application/providers/log_provider.dart';
import '../../application/services/log_service.dart';
import '../../domain/entities/backup_log.dart';
import '../widgets/common/common.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LogProvider>().loadLogs();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      final provider = context.read<LogProvider>();
      if (provider.hasMore && !provider.isLoading) {
        provider.loadMore();
      }
    }
  }

  Future<void> _handleClearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Limpar Logs'),
        content: const Text(
          'Tem certeza que deseja limpar todos os logs antigos? Esta ação não pode ser desfeita.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          Button(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await context.read<LogProvider>().cleanOldLogs();
      if (!mounted) return;

      MessageModal.showSuccess(context, message: 'Logs limpos com sucesso');
    }
  }

  Future<void> _handleExportLogs() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Exportar Logs',
      fileName:
          'backup_logs_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      type: FileType.custom,
      allowedExtensions: ['txt', 'json', 'csv'],
    );

    if (result == null) return;

    final format = _getFormatFromExtension(result);
    if (format == null) {
      if (mounted) {
        MessageModal.showWarning(
          context,
          message: 'Formato de arquivo não suportado',
        );
      }
      return;
    }

    final provider = context.read<LogProvider>();
    final filePath = await provider.exportLogs(
      outputPath: result,
      format: format,
    );

    if (filePath != null && mounted) {
      MessageModal.showInfo(
        context,
        message: 'Logs exportados para: $filePath',
      );
    } else if (mounted) {
      MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao exportar logs',
      );
    }
  }

  ExportFormat? _getFormatFromExtension(String path) {
    final extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'txt':
        return ExportFormat.txt;
      case 'json':
        return ExportFormat.json;
      case 'csv':
        return ExportFormat.csv;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Logs'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.delete),
              label: const Text('Limpar Logs'),
              onPressed: _handleClearLogs,
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.download),
              label: const Text('Exportar'),
              onPressed: _handleExportLogs,
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilters(context),
            const SizedBox(height: 16),
            Expanded(
              child: Consumer<LogProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading && provider.logs.isEmpty) {
                    return const Center(child: ProgressRing());
                  }

                  if (provider.error != null && provider.logs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            FluentIcons.error,
                            size: 48,
                            color: AppColors.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            provider.error!,
                            style: FluentTheme.of(
                              context,
                            ).typography.body?.copyWith(color: AppColors.error),
                          ),
                          const SizedBox(height: 16),
                          ActionButton(
                            label: 'Tentar Novamente',
                            onPressed: () => provider.refresh(),
                            icon: FluentIcons.refresh,
                          ),
                        ],
                      ),
                    );
                  }

                  if (provider.logs.isEmpty) {
                    return const AppCard(
                      child: EmptyState(
                        icon: FluentIcons.document,
                        message: 'Nenhum log registrado',
                      ),
                    );
                  }

                  return AppCard(
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            controller: _scrollController,
                            itemCount:
                                provider.logs.length +
                                (provider.hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == provider.logs.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: ProgressRing()),
                                );
                              }

                              final log = provider.logs[index];
                              return _LogListItem(log: log);
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    return Consumer<LogProvider>(
      builder: (context, provider, child) {
        return AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _searchController,
                  label: 'Buscar',
                  hint: 'Digite para buscar nos logs...',
                  prefixIcon: const Icon(FluentIcons.search),
                  onChanged: (value) {
                    provider.setSearchQuery(value);
                  },
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 150,
                child: AppDropdown<LogLevel?>(
                  label: 'Nível',
                  value: provider.filterLevel,
                  placeholder: const Text('Nível'),
                  items: [
                    ComboBoxItem(value: null, child: const Text('Todos')),
                    ...LogLevel.values.map(
                      (level) => ComboBoxItem<LogLevel?>(
                        value: level,
                        child: Text(_getLevelLabel(level)),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    provider.setFilterLevel(value);
                  },
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 150,
                child: AppDropdown<LogCategory?>(
                  label: 'Categoria',
                  value: provider.filterCategory,
                  placeholder: const Text('Categoria'),
                  items: [
                    ComboBoxItem(value: null, child: const Text('Todas')),
                    ...LogCategory.values.map(
                      (category) => ComboBoxItem<LogCategory?>(
                        value: category,
                        child: Text(_getCategoryLabel(category)),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    provider.setFilterCategory(value);
                  },
                ),
              ),
              if (provider.filterLevel != null ||
                  provider.filterCategory != null ||
                  provider.searchQuery.isNotEmpty) ...[
                const SizedBox(width: 16),
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: IconButton(
                    icon: const Icon(FluentIcons.clear),
                    onPressed: () {
                      _searchController.clear();
                      provider.clearFilters();
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _getLevelLabel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'Debug';
      case LogLevel.info:
        return 'Info';
      case LogLevel.warning:
        return 'Aviso';
      case LogLevel.error:
        return 'Erro';
    }
  }

  String _getCategoryLabel(LogCategory category) {
    switch (category) {
      case LogCategory.execution:
        return 'Execução';
      case LogCategory.system:
        return 'Sistema';
      case LogCategory.audit:
        return 'Auditoria';
    }
  }
}

class _LogListItem extends StatelessWidget {
  final BackupLog log;

  const _LogListItem({required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: FluentTheme.of(context).resources.controlStrokeColorDefault,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _getLevelIcon(log.level),
            color: _getLevelColor(context, log.level),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.message,
                        style: FluentTheme.of(context).typography.body,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('dd/MM/yyyy HH:mm:ss').format(log.createdAt),
                      style: FluentTheme.of(context).typography.caption,
                    ),
                  ],
                ),
                if (log.details != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    log.details!,
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    _Chip(
                      label: _getLevelLabel(log.level),
                      color: _getLevelColor(context, log.level),
                    ),
                    const SizedBox(width: 8),
                    _Chip(
                      label: _getCategoryLabel(log.category),
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getLevelIcon(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return FluentIcons.bug;
      case LogLevel.info:
        return FluentIcons.info;
      case LogLevel.warning:
        return FluentIcons.warning;
      case LogLevel.error:
        return FluentIcons.error;
    }
  }

  Color _getLevelColor(BuildContext context, LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return AppColors.logDebug;
      case LogLevel.info:
        return AppColors.primary;
      case LogLevel.warning:
        return AppColors.logWarning;
      case LogLevel.error:
        return AppColors.error;
    }
  }

  String _getLevelLabel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'Debug';
      case LogLevel.info:
        return 'Info';
      case LogLevel.warning:
        return 'Aviso';
      case LogLevel.error:
        return 'Erro';
    }
  }

  String _getCategoryLabel(LogCategory category) {
    switch (category) {
      case LogCategory.execution:
        return 'Execução';
      case LogCategory.system:
        return 'Sistema';
      case LogCategory.audit:
        return 'Auditoria';
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
