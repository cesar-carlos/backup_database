import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/remote_file_entry.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class TransferBackupsPage extends StatefulWidget {
  const TransferBackupsPage({super.key});

  @override
  State<TransferBackupsPage> createState() => _TransferBackupsPageState();
}

class _TransferBackupsPageState extends State<TransferBackupsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<ServerConnectionProvider>().isConnected) {
        final provider = context.read<RemoteFileTransferProvider>();
        provider.loadAvailableFiles();
        provider.loadTransferHistory();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('Transferir Backups')),
      content: Consumer<ServerConnectionProvider>(
        builder: (context, connectionProvider, _) {
          if (!connectionProvider.isConnected) {
            return _buildNotConnected(context);
          }
          return Consumer<RemoteFileTransferProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading && provider.files.isEmpty) {
                return const Center(child: ProgressRing());
              }
              if (provider.error != null && provider.files.isEmpty) {
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
                          onPressed: () => provider.loadAvailableFiles(),
                          child: const Text('Tentar Novamente'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (provider.files.isEmpty) {
                return AppCard(
                  child: EmptyState(
                    icon: FluentIcons.fabric_folder,
                    message: 'Nenhum arquivo disponível no servidor',
                    actionLabel: 'Atualizar',
                    onAction: () => provider.loadAvailableFiles(),
                  ),
                );
              }
              return _buildFileList(context, provider);
            },
          );
        },
      ),
    );
  }

  Widget _buildNotConnected(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.plug_disconnected,
              size: 64,
              color: FluentTheme.of(context).resources.textFillColorSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Conecte-se a um servidor',
              style: FluentTheme.of(context).typography.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Vá em Conectar para adicionar e conectar a um servidor, '
              'depois volte aqui para transferir backups.',
              style: FluentTheme.of(context).typography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/server-login'),
              child: const Text('Ir para Conectar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList(
    BuildContext context,
    RemoteFileTransferProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (provider.error != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: InfoBar(
              title: const Text('Aviso'),
              content: Text(provider.error!),
              severity: InfoBarSeverity.error,
              onClose: () => provider.clearError(),
            ),
          ),
        ],
        CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: provider.isLoading
                  ? null
                  : () => provider.loadAvailableFiles(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: ListView.separated(
                  itemCount: provider.files.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final entry = provider.files[index];
                    final isSelected =
                        provider.selectedFile?.path == entry.path;
                    return _RemoteFileListItem(
                      entry: entry,
                      isSelected: isSelected,
                      onTap: () => provider.setSelectedFile(
                        isSelected ? null : entry,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildTransferPanel(context, provider),
              ),
            ],
          ),
        ),
        _buildHistorySection(context, provider),
      ],
    );
  }

  Widget _buildHistorySection(
    BuildContext context,
    RemoteFileTransferProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        Text(
          'Histórico de transferências',
          style: FluentTheme.of(context).typography.subtitle,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: provider.transferHistory.isEmpty
              ? Center(
                  child: Text(
                    'Nenhuma transferência registrada',
                    style: FluentTheme.of(context).typography.body,
                  ),
                )
              : ListView.separated(
                  itemCount: provider.transferHistory.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final entry = provider.transferHistory[index];
                    return _TransferHistoryListItem(entry: entry);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTransferPanel(
    BuildContext context,
    RemoteFileTransferProvider provider,
  ) {
    return _TransferPanel(provider: provider);
  }
}

class _TransferPanel extends StatefulWidget {
  const _TransferPanel({required this.provider});

  final RemoteFileTransferProvider provider;

  @override
  State<_TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends State<_TransferPanel> {
  late TextEditingController _outputPathController;
  bool _saveAsDefault = false;
  String? _selectedScheduleId;

  @override
  void initState() {
    super.initState();
    _outputPathController = TextEditingController(
      text: widget.provider.outputPath,
    );
  }

  @override
  void didUpdateWidget(covariant _TransferPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.provider.outputPath != _outputPathController.text) {
      _outputPathController.text = widget.provider.outputPath;
    }
  }

  @override
  void dispose() {
    _outputPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Destino',
              style: FluentTheme.of(context).typography.subtitle,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextBox(
                    controller: _outputPathController,
                    placeholder: 'Pasta de destino',
                    onChanged: provider.setOutputPath,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(FluentIcons.folder_open),
                  onPressed: () => _selectOutputFolder(provider),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Checkbox(
              checked: _saveAsDefault,
              onChanged: (value) {
                setState(() => _saveAsDefault = value ?? false);
              },
              content: const Text(
                'Salvar como pasta padrão para backups recebidos',
              ),
            ),
            _buildScheduleDropdown(context, provider),
            _buildSendAlsoToSection(context, provider),
            if (provider.uploadError != null) ...[
              const SizedBox(height: 8),
              InfoBar(
                title: const Text('Envio para destinos remotos'),
                content: Text(provider.uploadError!),
                severity: InfoBarSeverity.warning,
                onClose: provider.clearUploadError,
              ),
            ],
            if (provider.isUploadingToRemotes) ...[
              const SizedBox(height: 8),
              Text(
                'Enviando para destinos remotos...',
                style: FluentTheme.of(context).typography.body,
              ),
            ],
            if (provider.isTransferring &&
                provider.transferTotalChunks != null &&
                provider.transferTotalChunks! > 0) ...[
              const SizedBox(height: 16),
              Text(
                'Transferindo... ${provider.transferCurrentChunk ?? 0} de ${provider.transferTotalChunks} '
                '(${provider.transferProgress != null ? (provider.transferProgress! * 100).toStringAsFixed(0) : '0'}%)',
                style: FluentTheme.of(context).typography.body,
              ),
              const SizedBox(height: 8),
              _TransferProgressBar(
                value: provider.transferProgress ?? 0.0,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: provider.isTransferring ||
                      provider.isUploadingToRemotes ||
                      provider.selectedFile == null
                  ? null
                  : () => _startTransfer(context, provider),
              child: provider.isTransferring &&
                      (provider.transferTotalChunks == null ||
                          provider.transferTotalChunks! == 0)
                  ? const ProgressRing(strokeWidth: 2)
                  : const Text('Transferir'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleDropdown(
    BuildContext context,
    RemoteFileTransferProvider provider,
  ) {
    return Consumer<RemoteSchedulesProvider>(
      builder: (context, schedulesProvider, _) {
        final schedules = schedulesProvider.schedules;
        if (schedules.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              'Agendamento (preencher destinos)',
              style: FluentTheme.of(context).typography.subtitle,
            ),
            const SizedBox(height: 8),
            ComboBox<String?>(
              value: _selectedScheduleId,
              items: [
                const ComboBoxItem<String?>(
                  child: Text('Nenhum'),
                ),
                ...schedules.map(
                  (s) => ComboBoxItem<String?>(
                    value: s.id,
                    child: Text(s.name),
                  ),
                ),
              ],
              onChanged: provider.isTransferring || provider.isUploadingToRemotes
                  ? null
                  : (String? value) async {
                      setState(() => _selectedScheduleId = value);
                      if (value != null && value.isNotEmpty) {
                        final ids = await provider.getLinkedDestinationIds(
                          value,
                        );
                        provider.setSelectedDestinationIds(ids.toSet());
                      }
                    },
            ),
          ],
        );
      },
    );
  }

  Widget _buildSendAlsoToSection(
    BuildContext context,
    RemoteFileTransferProvider provider,
  ) {
    return Consumer<DestinationProvider>(
      builder: (context, destinationProvider, _) {
        final destinations = destinationProvider.destinations;
        if (destinations.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              'Enviar também para',
              style: FluentTheme.of(context).typography.subtitle,
            ),
            const SizedBox(height: 8),
            ...destinations.map(
              (d) => Checkbox(
                checked: provider.selectedDestinationIds.contains(d.id),
                onChanged: provider.isTransferring || provider.isUploadingToRemotes
                    ? null
                    : (value) => provider.toggleSelectedDestination(d.id),
                content: Row(
                  children: [
                    Text(d.name),
                    const SizedBox(width: 8),
                    _DestinationTypeBadge(type: d.type),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectOutputFolder(RemoteFileTransferProvider provider) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Selecionar pasta de destino',
    );
    if (result != null) {
      provider.setOutputPath(result);
      if (mounted) {
        _outputPathController.text = result;
      }
    }
  }

  Future<void> _startTransfer(
    BuildContext context,
    RemoteFileTransferProvider provider,
  ) async {
    if (_saveAsDefault &&
        provider.outputPath.trim().isNotEmpty) {
      await provider.setDefaultOutputPath(provider.outputPath);
    }
    final success = await provider.requestFile();
    if (context.mounted) {
      if (success) {
        if (provider.uploadError != null) {
          MessageModal.showWarning(
            context,
            message:
                'Arquivo transferido. Alguns envios remotos falharam: '
                '${provider.uploadError}',
          );
        } else {
          MessageModal.showSuccess(
            context,
            message: 'Arquivo transferido com sucesso.',
          );
        }
      } else {
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao transferir.',
        );
      }
    }
  }
}

class _TransferHistoryListItem extends StatelessWidget {
  const _TransferHistoryListItem({required this.entry});
  final FileTransferHistoryEntry entry;

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final isCompleted = entry.status == 'completed';
    return ListTile(
      leading: Icon(
        isCompleted ? FluentIcons.check_mark : FluentIcons.error,
        color: isCompleted
            ? theme.resources.systemFillColorSuccessBackground
            : AppColors.error,
      ),
      title: Text(entry.fileName),
      subtitle: Text(
        '${_formatSize(entry.fileSize)} · '
        '${entry.completedAt != null ? dateFormat.format(entry.completedAt!) : '-'} · '
        '${isCompleted ? 'Concluído' : 'Falhou'}',
      ),
    );
  }
}

class _TransferProgressBar extends StatelessWidget {
  const _TransferProgressBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0.0, 1.0);
    final theme = FluentTheme.of(context);

    return Container(
      width: double.infinity,
      height: 8,
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              color: theme.resources.cardBackgroundFillColorDefault,
            ),
            FractionallySizedBox(
              widthFactor: clampedValue,
              alignment: Alignment.centerLeft,
              child: Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: theme.accentColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteFileListItem extends StatelessWidget {
  const _RemoteFileListItem({
    required this.entry,
    required this.isSelected,
    required this.onTap,
  });

  final RemoteFileEntry entry;
  final bool isSelected;
  final VoidCallback onTap;

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final theme = FluentTheme.of(context);
    return Container(
      decoration: isSelected
          ? BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: ListTile(
        leading: const Icon(FluentIcons.document),
        title: Text(entry.path),
        subtitle: Text(
          '${_formatSize(entry.size)} · ${dateFormat.format(entry.lastModified)}',
        ),
        onPressed: onTap,
      ),
    );
  }
}

class _DestinationTypeBadge extends StatelessWidget {
  const _DestinationTypeBadge({required this.type});

  final DestinationType type;

  String get _label {
    switch (type) {
      case DestinationType.local:
        return 'LOCAL';
      case DestinationType.ftp:
        return 'FTP';
      case DestinationType.googleDrive:
        return 'Google Drive';
      case DestinationType.dropbox:
        return 'Dropbox';
      case DestinationType.nextcloud:
        return 'Nextcloud';
    }
  }

  Color _color(FluentThemeData theme) {
    switch (type) {
      case DestinationType.local:
        return theme.resources.systemFillColorSuccessBackground;
      case DestinationType.ftp:
        return const Color(0xFF0066CC);
      case DestinationType.googleDrive:
        return const Color(0xFF4285F4);
      case DestinationType.dropbox:
        return const Color(0xFF0061FF);
      case DestinationType.nextcloud:
        return const Color(0xFF0082C9);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color(theme).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _color(theme),
          width: 1,
        ),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: _color(theme),
        ),
      ),
    );
  }
}
