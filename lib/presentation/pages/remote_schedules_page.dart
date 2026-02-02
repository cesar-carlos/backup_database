import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/schedules/schedules.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class RemoteSchedulesPage extends StatefulWidget {
  const RemoteSchedulesPage({super.key});

  @override
  State<RemoteSchedulesPage> createState() => _RemoteSchedulesPageState();
}

class _RemoteSchedulesPageState extends State<RemoteSchedulesPage> {
  ServerConnectionProvider? _connectionProvider;
  bool _hasLoadedInitialSchedules = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectionProvider = context.read<ServerConnectionProvider>();
      _connectionProvider!.addListener(_onConnectionChanged);

      if (_connectionProvider!.isConnected) {
        context.read<RemoteSchedulesProvider>().loadSchedules();
        _hasLoadedInitialSchedules = true;
      }
    });
  }

  @override
  void dispose() {
    _connectionProvider?.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    if (_connectionProvider == null) return;

    if (_connectionProvider!.isConnected && !_hasLoadedInitialSchedules) {
      context.read<RemoteSchedulesProvider>().loadSchedules();
      _hasLoadedInitialSchedules = true;
    }

    if (!_connectionProvider!.isConnected) {
      _hasLoadedInitialSchedules = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('Agendamentos do Servidor')),
      content: PageContentLayout(
        children: [
          Consumer<RemoteSchedulesProvider>(
            builder: (context, provider, _) {
              if (provider.isExecuting &&
                  provider.backupMessage != null &&
                  provider.executingScheduleId != null) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildBackupProgressCard(context, provider),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Consumer<ServerConnectionProvider>(
            builder: (context, connectionProvider, _) {
              if (!connectionProvider.isConnected) {
                return _buildNotConnected(context);
              }
              return Consumer<RemoteSchedulesProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading && provider.schedules.isEmpty) {
                    return const Center(child: ProgressRing());
                  }
                  if (provider.error != null && provider.schedules.isEmpty) {
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
                              style:
                                  FluentTheme.of(context).typography.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Button(
                              onPressed: () => provider.loadSchedules(),
                              child: const Text('Tentar Novamente'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (provider.schedules.isEmpty) {
                    return AppCard(
                      child: EmptyState(
                        icon: FluentIcons.calendar,
                        message: 'Nenhum agendamento no servidor',
                        actionLabel: 'Atualizar',
                        onAction: () => provider.loadSchedules(),
                      ),
                    );
                  }
                  return _buildScheduleList(context, provider);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNotConnected(BuildContext context) {
    return Center(
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
            'depois volte aqui para ver e controlar os agendamentos.',
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
    );
  }

  Widget _buildScheduleList(
    BuildContext context,
    RemoteSchedulesProvider provider,
  ) {
    return Expanded(
      child: Column(
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
                onPressed: () => provider.loadSchedules(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: provider.schedules.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final schedule = provider.schedules[index];
                final isOperating = schedule.id == provider.updatingScheduleId ||
                    schedule.id == provider.executingScheduleId;
                return ScheduleListItem(
                  schedule: schedule,
                  isOperating: isOperating,
                  onToggleEnabled: schedule.id == provider.updatingScheduleId
                      ? null
                      : (enabled) => _onToggleEnabled(
                            context,
                            provider,
                            schedule,
                            enabled,
                          ),
                  onRunNow: schedule.id == provider.executingScheduleId ||
                          !schedule.enabled
                      ? null
                      : () => _onRunNow(context, provider, schedule.id),
                  onTransferDestinations:
                      schedule.id == provider.updatingScheduleId ||
                              schedule.id == provider.executingScheduleId
                          ? null
                          : () => _showTransferDestinationsDialog(
                                context,
                                schedule,
                              ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onToggleEnabled(
    BuildContext context,
    RemoteSchedulesProvider provider,
    Schedule schedule,
    bool enabled,
  ) async {
    if (provider.updatingScheduleId != null) return;

    final updated = schedule.copyWith(enabled: enabled);
    final success = await provider.updateSchedule(updated);
    if (context.mounted) {
      if (success) {
        MessageModal.showSuccess(
          context,
          message: enabled ? 'Agendamento ativado.' : 'Agendamento desativado.',
        );
      } else {
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao atualizar.',
        );
      }
    }
  }

  Future<void> _onRunNow(
    BuildContext context,
    RemoteSchedulesProvider provider,
    String scheduleId,
  ) async {
    if (provider.executingScheduleId != null) return;

    final success = await provider.executeSchedule(scheduleId);
    if (context.mounted) {
      if (success) {
        MessageModal.showSuccess(
          context,
          message: 'Execução iniciada no servidor.',
        );
        provider.loadSchedules();
      } else {
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao executar.',
        );
      }
    }
  }

  Future<void> _showTransferDestinationsDialog(
    BuildContext context,
    Schedule schedule,
  ) async {
    final transferProvider = context.read<RemoteFileTransferProvider>();
    final destinationProvider = context.read<DestinationProvider>();
    final destinations = destinationProvider.destinations;
    if (destinations.isEmpty) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => ContentDialog(
            title: const Text('Destinos após transferir'),
            content: const Text(
              'Cadastre destinos em Destinos para vincular aqui.',
            ),
            actions: [
              Button(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final linkedIds = await transferProvider.getLinkedDestinationIds(
      schedule.id,
    );
    final selectedIds = Set<String>.from(linkedIds);

    if (!context.mounted) return;
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _TransferDestinationsDialog(
        scheduleName: schedule.name,
        destinations: destinations,
        initialSelectedIds: selectedIds,
      ),
    );

    if (result != null && context.mounted) {
      await transferProvider.setLinkedDestinationIds(
        schedule.id,
        result.toList(),
      );
      if (context.mounted) {
        MessageModal.showSuccess(
          context,
          message: 'Destinos vinculados ao agendamento.',
        );
      }
    }
  }
}

class _TransferDestinationsDialog extends StatefulWidget {
  const _TransferDestinationsDialog({
    required this.scheduleName,
    required this.destinations,
    required this.initialSelectedIds,
  });

  final String scheduleName;
  final List<BackupDestination> destinations;
  final Set<String> initialSelectedIds;

  @override
  State<_TransferDestinationsDialog> createState() =>
      _TransferDestinationsDialogState();
}

class _TransferDestinationsDialogState
    extends State<_TransferDestinationsDialog> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('Destinos após transferir'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ao transferir um backup do agendamento "${widget.scheduleName}", '
              'enviar também para:',
              style: FluentTheme.of(context).typography.body,
            ),
            const SizedBox(height: 16),
            ...widget.destinations.map(
              (d) => Checkbox(
                checked: _selectedIds.contains(d.id),
                onChanged: (value) {
                  setState(() {
                    if (value ?? false) {
                      _selectedIds.add(d.id);
                    } else {
                      _selectedIds.remove(d.id);
                    }
                  });
                },
                content: Row(
                  children: [
                    Text(d.name),
                    const SizedBox(width: 8),
                    DestinationTypeBadge(type: d.type),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedIds),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

Widget _buildBackupProgressCard(
  BuildContext context,
  RemoteSchedulesProvider provider,
) {
  final schedule = provider.schedules.firstWhere(
    (s) => s.id == provider.executingScheduleId,
    orElse: () => provider.schedules.first,
  );

  return AppCard(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ProgressRing(strokeWidth: 2),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Executando backup no servidor',
                      style: FluentTheme.of(context).typography.subtitle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      schedule.name,
                      style:
                          FluentTheme.of(context).typography.bodyStrong,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (provider.backupStep != null) ...[
            const SizedBox(height: 12),
            Text(
              provider.backupStep!,
              style: FluentTheme.of(context).typography.caption,
            ),
          ],
          if (provider.backupMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              provider.backupMessage!,
              style: FluentTheme.of(context).typography.body,
            ),
          ],
          if (provider.backupProgress != null) ...[
            const SizedBox(height: 8),
            ProgressBar(
              value: provider.backupProgress! * 100,
            ),
          ],
        ],
      ),
    ),
  );
}
