import 'dart:async';

import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/utils/integrity_error_modal_helper.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/remote/remote_backup_preflight_dialog.dart';
import 'package:backup_database/presentation/widgets/remote_schedules/remote_schedules.dart';
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
  bool? _wasConnected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectionProvider = context.read<ServerConnectionProvider>();
      _connectionProvider!.addListener(_onConnectionChanged);

      final isConnected = _connectionProvider!.isConnected;
      _wasConnected = isConnected;
      if (isConnected) {
        _loadConnectedRemoteData(context);
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

    final isConnected = _connectionProvider!.isConnected;
    final wasConnected = _wasConnected ?? false;
    _wasConnected = isConnected;

    if (isConnected && !wasConnected) {
      // §audit-2026-05-28 wave 2 (P1): `tryResumeExecutionAfterReconnect`
      // é responsabilidade do `ServerConnectionProvider`, que escuta
      // `ConnectionStatus` de forma global. Antes, esta página também
      // disparava o resume — quando o usuário estava aqui no momento
      // da reconexão, os dois caminhos rodavam em paralelo e dobravam
      // o download. A página continua reidratando listas (schedules,
      // queue, status do servidor) via `_loadConnectedRemoteData`,
      // que é idempotente.
      _loadConnectedRemoteData(context);
    }
  }

  void _loadConnectedRemoteData(BuildContext context) {
    unawaited(context.read<RemoteSchedulesProvider>().loadSchedules());
    unawaited(context.read<RemoteSchedulesProvider>().loadExecutionQueue());
    unawaited(context.read<ServerConnectionProvider>().refreshServerStatus());
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Agendamentos do Servidor',
      headerBottom: Consumer<ServerConnectionProvider>(
        builder: (context, connectionProvider, _) {
          if (!connectionProvider.isConnected) {
            return const SizedBox.shrink();
          }
          return Align(
            alignment: Alignment.centerLeft,
            child: HyperlinkButton(
              onPressed: () => context.go(RouteNames.remoteDatabaseConfigs),
              child: Text(
                appLocaleString(
                  context,
                  'Bancos no servidor',
                  'Server databases',
                ),
              ),
            ),
          );
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Consumer<RemoteSchedulesProvider>(
            builder: (context, provider, _) {
              if (provider.isExecuting &&
                  provider.backupMessage != null &&
                  provider.executingScheduleId != null) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: RemoteBackupProgressCard(
                    provider: provider,
                    onCancel: () => _onCancelBackup(context, provider),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Consumer2<ServerConnectionProvider, RemoteSchedulesProvider>(
            builder: (context, connectionProvider, schedulesProvider, _) {
              if (!connectionProvider.isConnected ||
                  !connectionProvider.isExecutionQueueSupported) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: ServerExecutionQueueCard(
                  provider: schedulesProvider,
                  scheduleNameFor: _scheduleLabel,
                ),
              );
            },
          ),
          Expanded(
            child: Consumer<ServerConnectionProvider>(
              builder: (context, connectionProvider, _) {
                if (!connectionProvider.isConnected) {
                  return const RemoteSchedulesNotConnected();
                }
                return Consumer<RemoteSchedulesProvider>(
                  builder: (context, provider, _) {
                    if (provider.isLoading && provider.schedules.isEmpty) {
                      return AppPageState.loading(
                        title: 'Carregando agendamentos remotos',
                        message: 'Sincronizando os agendamentos do servidor conectado.',
                      );
                    }
                    if (provider.error != null && provider.schedules.isEmpty) {
                      return AppPageState.error(
                        title: 'Falha ao carregar agendamentos remotos',
                        message: provider.error,
                        actionLabel: 'Tentar novamente',
                        onAction: () => unawaited(provider.loadSchedules()),
                      );
                    }
                    if (provider.schedules.isEmpty) {
                      return AppPageState.empty(
                        title: 'Nenhum agendamento no servidor',
                        message: 'Veja e controle os agendamentos publicados pelo servidor conectado.',
                        actionLabel: 'Atualizar',
                        onAction: () => unawaited(provider.loadSchedules()),
                      );
                    }
                    return RemoteSchedulesListView(
                      provider: provider,
                      connectionProvider: connectionProvider,
                      onCreatePressed: () => _showCreateRemoteScheduleDialog(
                        context,
                        provider,
                      ),
                      onToggleEnabled: (schedule, enabled) =>
                          _onToggleSchedulePaused(
                            context,
                            provider,
                            schedule,
                            enabled,
                          ),
                      onDelete: (schedule) => _onDeleteRemoteSchedule(
                        context,
                        provider,
                        schedule,
                      ),
                      onRunNow: (scheduleId) => _onRunNow(
                        context,
                        provider,
                        scheduleId,
                        connectionProvider,
                      ),
                      onTransferDestinations: (schedule) =>
                          _showTransferDestinationsDialog(context, schedule),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _scheduleLabel(RemoteSchedulesProvider provider, String scheduleId) {
    for (final schedule in provider.schedules) {
      if (schedule.id == scheduleId) {
        return schedule.name;
      }
    }
    return scheduleId;
  }

  Future<void> _showCreateRemoteScheduleDialog(
    BuildContext context,
    RemoteSchedulesProvider provider,
  ) async {
    final template = provider.schedules.isNotEmpty
        ? provider.schedules.first
        : null;
    final draft = await showDialog<Schedule>(
      context: context,
      builder: (context) => RemoteScheduleCreateDialog(template: template),
    );
    if (draft == null || !context.mounted) return;

    final success = await provider.createRemoteSchedule(draft);
    if (!context.mounted) return;
    if (success) {
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Agendamento criado no servidor.',
            'Schedule created on server.',
          ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao criar agendamento.',
        ),
      );
    }
  }

  Future<void> _onToggleSchedulePaused(
    BuildContext context,
    RemoteSchedulesProvider provider,
    Schedule schedule,
    bool enabled,
  ) async {
    if (provider.updatingScheduleId != null) return;

    final success = await provider.setRemoteSchedulePaused(
      scheduleId: schedule.id,
      paused: !enabled,
    );
    if (context.mounted) {
      if (success) {
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: enabled
                ? appLocaleString(
                    context,
                    'Agendamento retomado.',
                    'Schedule resumed.',
                  )
                : appLocaleString(
                    context,
                    'Agendamento pausado.',
                    'Schedule paused.',
                  ),
          ),
        );
      } else {
        unawaited(
          MessageModal.showError(
            context,
            message: provider.error ?? 'Erro ao atualizar agendamento.',
          ),
        );
      }
    }
  }

  Future<void> _onDeleteRemoteSchedule(
    BuildContext context,
    RemoteSchedulesProvider provider,
    Schedule schedule,
  ) async {
    if (provider.updatingScheduleId != null) return;

    final confirmed = await MessageModal.showConfirm(
      context,
      title: appLocaleString(
        context,
        'Excluir agendamento',
        'Delete schedule',
      ),
      message: appLocaleString(
        context,
        'Excluir "${schedule.name}" no servidor? Esta ação não pode ser desfeita.',
        'Delete "${schedule.name}" on the server? This cannot be undone.',
      ),
      confirmLabel: appLocaleString(context, 'Excluir', 'Delete'),
    );

    if (confirmed && context.mounted) {
      final success = await provider.deleteRemoteSchedule(schedule.id);
      if (context.mounted) {
        if (success) {
          unawaited(
            FluentInfoBarFeedback.showSuccess(
              context,
              message: appLocaleString(
                context,
                'Agendamento excluído no servidor.',
                'Schedule deleted on server.',
              ),
            ),
          );
        } else {
          unawaited(
            MessageModal.showError(
              context,
              message: provider.error ?? 'Erro ao excluir agendamento.',
            ),
          );
        }
      }
    }
  }

  Future<void> _onRunNow(
    BuildContext context,
    RemoteSchedulesProvider provider,
    String scheduleId,
    ServerConnectionProvider connectionProvider,
  ) async {
    if (provider.executingScheduleId != null) return;

    await connectionProvider.refreshServerStatus();
    if (!context.mounted) return;
    if (!connectionProvider.isServerHealthy) {
      unawaited(
        FluentInfoBarFeedback.showWarning(
          context,
          message: appLocaleString(
            context,
            'O servidor não está saudável. Atualize o status e tente novamente.',
            'Server is not healthy. Refresh status and try again.',
          ),
        ),
      );
      return;
    }

    final preflight = await provider.runPreflightForSchedule();
    if (!context.mounted) return;

    if (preflight.errorMessage != null) {
      unawaited(
        FluentInfoBarFeedback.showWarning(
          context,
          message: preflight.errorMessage!,
        ),
      );
      return;
    }

    var skipPreflightCheck =
        preflight.action == RemotePreflightUiAction.proceed;
    if (preflight.action == RemotePreflightUiAction.showDialog &&
        preflight.preflight != null) {
      final proceed = await showRemoteBackupPreflightDialog(
        context: context,
        preflight: preflight.preflight!,
      );
      if (!context.mounted) return;
      if (preflight.isBlocked || proceed != true) {
        return;
      }
      skipPreflightCheck = true;
    }

    final success = await provider.executeSchedule(
      scheduleId,
      skipPreflightCheck: skipPreflightCheck,
    );
    if (context.mounted) {
      if (success) {
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: 'Execução iniciada no servidor.',
          ),
        );
        await provider.loadSchedules();
        unawaited(connectionProvider.refreshServerStatus());
      } else {
        final code = provider.lastErrorCode;
        final message = provider.error ?? 'Erro ao executar.';
        IntegrityErrorModalHelper.showExecutionErrorModal(
          context: context,
          failureCode: code,
          message: message,
        );
      }
    }
  }

  Future<void> _onCancelBackup(
    BuildContext context,
    RemoteSchedulesProvider provider,
  ) async {
    final confirmed = await MessageModal.showConfirm(
      context,
      title: 'Cancelar backup',
      message: 'Deseja cancelar o backup em execução no servidor?',
      confirmLabel: 'Sim, cancelar',
    );

    if (confirmed && context.mounted) {
      final success = await provider.cancelSchedule();
      if (context.mounted) {
        if (success) {
          unawaited(
            FluentInfoBarFeedback.showSuccess(
              context,
              message: 'Backup cancelado no servidor.',
            ),
          );
        } else {
          unawaited(
            MessageModal.showError(
              context,
              message: provider.error ?? 'Erro ao cancelar backup.',
            ),
          );
        }
      }
    }
  }

  Future<void> _showTransferDestinationsDialog(
    BuildContext context,
    Schedule schedule,
  ) async {
    final transferProvider = context.read<RemoteFileTransferProvider>();
    final destinationProvider = context.read<DestinationProvider>();

    if (destinationProvider.destinations.isEmpty ||
        destinationProvider.isLoading) {
      await destinationProvider.loadDestinations();
    }
    if (!context.mounted) return;

    final destinations = destinationProvider.destinations;
    if (destinations.isEmpty) {
      await MessageModal.showInfo(
        context,
        title: 'Destinos após transferir',
        message: 'Cadastre destinos em Destinos para vincular aqui.',
      );
      return;
    }

    final linkedIds = await transferProvider.getLinkedDestinationIds(
      schedule.id,
    );
    final selectedIds = Set<String>.from(linkedIds);

    if (!context.mounted) return;
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => TransferDestinationsDialog(
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
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: 'Destinos vinculados ao agendamento.',
          ),
        );
      }
    }
  }
}
