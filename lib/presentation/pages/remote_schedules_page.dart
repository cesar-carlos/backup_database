import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/core/utils/database_type_metadata.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/presentation/utils/integrity_error_modal_helper.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/remote/remote_backup_preflight_dialog.dart';
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
      _loadConnectedRemoteData(context);
      unawaited(
        context
            .read<RemoteSchedulesProvider>()
            .tryResumeExecutionAfterReconnect(),
      );
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
                  child: _BackupProgressCard(
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
                child: _ServerExecutionQueueCard(
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
                  return _buildNotConnected(context);
                }
                return Consumer<RemoteSchedulesProvider>(
                  builder: (context, provider, _) {
                    if (provider.isLoading && provider.schedules.isEmpty) {
                      return AppPageState.loading(
                        title: 'Carregando agendamentos remotos',
                        message:
                            'Sincronizando os agendamentos do servidor conectado.',
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
                        message:
                            'Veja e controle os agendamentos publicados pelo servidor conectado.',
                        actionLabel: 'Atualizar',
                        onAction: () => unawaited(provider.loadSchedules()),
                      );
                    }
                    return _buildScheduleList(
                      context,
                      provider,
                      connectionProvider: connectionProvider,
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

  bool _isDisconnectionError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('desconectado') ||
        lower.contains('conexao perdida') ||
        lower.contains('conexão perdida') ||
        lower.contains('reconecte-se');
  }

  Widget _buildNotConnected(BuildContext context) {
    return AppPageState.empty(
      title: 'Conecte-se a um servidor',
      message:
          'Vá em Conectar para adicionar e conectar a um servidor, depois volte aqui para ver e controlar os agendamentos.',
      actionLabel: 'Ir para Conectar',
      onAction: () => context.go(RouteNames.serverLogin),
    );
  }

  Widget _buildScheduleList(
    BuildContext context,
    RemoteSchedulesProvider provider, {
    required ServerConnectionProvider connectionProvider,
  }) {
    final partialError = provider.error;
    final health = connectionProvider.serverHealth;
    final isServerHealthy = connectionProvider.isServerHealthy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isServerHealthy) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Servidor indisponível para backup',
                  'Server unavailable for backup',
                ),
              ),
              content: SelectableText(
                health?.message ??
                    appLocaleString(
                      context,
                      'Atualize o status do servidor ou aguarde a recuperação '
                          'antes de executar backups remotos.',
                      'Refresh server status or wait for recovery before '
                          'running remote backups.',
                    ),
              ),
              severity: health?.isUnhealthy ?? true
                  ? InfoBarSeverity.error
                  : InfoBarSeverity.warning,
              action: Button(
                onPressed: connectionProvider.isRefreshingStatus
                    ? null
                    : () => unawaited(
                        connectionProvider.refreshServerStatus(),
                      ),
                child: Text(
                  appLocaleString(
                    context,
                    'Atualizar status',
                    'Refresh status',
                  ),
                ),
              ),
            ),
          ),
        ],
        if (partialError != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: InfoBar(
              title: const Text('Aviso'),
              content: SelectableText.rich(
                TextSpan(
                  text: partialError,
                  style: FluentTheme.of(context).typography.body?.copyWith(
                    color: context.colors.danger,
                  ),
                ),
              ),
              severity: InfoBarSeverity.error,
              onClose: () => provider.clearError(),
              action: _isDisconnectionError(partialError)
                  ? Button(
                      onPressed: () {
                        provider.clearError();
                        context.go(RouteNames.serverLogin);
                      },
                      child: const Text('Reconectar'),
                    )
                  : null,
            ),
          ),
        ],
        CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: Text(
                appLocaleString(
                  context,
                  'Novo agendamento remoto',
                  'New remote schedule',
                ),
              ),
              onPressed: provider.isUpdating || provider.isExecuting
                  ? null
                  : () => _showCreateRemoteScheduleDialog(
                      context,
                      provider,
                    ),
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: provider.isUpdating || provider.isExecuting
                  ? null
                  : () {
                      unawaited(provider.loadSchedules());
                      unawaited(provider.loadExecutionQueue());
                      unawaited(
                        connectionProvider.refreshServerStatus(),
                      );
                    },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: ListView.separated(
            itemCount: provider.schedules.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final schedule = provider.schedules[index];
              final isOperating =
                  schedule.id == provider.updatingScheduleId ||
                  schedule.id == provider.executingScheduleId;
              return ScheduleListItem(
                schedule: schedule,
                isOperating: isOperating,
                onToggleEnabled: schedule.id == provider.updatingScheduleId
                    ? null
                    : (enabled) => _onToggleSchedulePaused(
                        context,
                        provider,
                        schedule,
                        enabled,
                      ),
                onDelete:
                    schedule.id == provider.updatingScheduleId ||
                        schedule.id == provider.executingScheduleId
                    ? null
                    : () => _onDeleteRemoteSchedule(
                        context,
                        provider,
                        schedule,
                      ),
                onRunNow:
                    schedule.id == provider.executingScheduleId ||
                        !schedule.enabled ||
                        !isServerHealthy
                    ? null
                    : () => _onRunNow(
                        context,
                        provider,
                        schedule.id,
                        connectionProvider,
                      ),
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
    );
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
      builder: (context) => _RemoteScheduleCreateDialog(template: template),
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(
          appLocaleString(
            context,
            'Excluir agendamento',
            'Delete schedule',
          ),
        ),
        content: Text(
          appLocaleString(
            context,
            'Excluir "${schedule.name}" no servidor? Esta ação não pode ser desfeita.',
            'Delete "${schedule.name}" on the server? This cannot be undone.',
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appLocaleString(context, 'Cancelar', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(appLocaleString(context, 'Excluir', 'Delete')),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Cancelar backup'),
        content: const Text(
          'Deseja cancelar o backup em execução no servidor?',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sim, cancelar'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
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

class _RemoteScheduleCreateDialog extends StatefulWidget {
  const _RemoteScheduleCreateDialog({this.template});

  final Schedule? template;

  @override
  State<_RemoteScheduleCreateDialog> createState() =>
      _RemoteScheduleCreateDialogState();
}

class _RemoteScheduleCreateDialogState
    extends State<_RemoteScheduleCreateDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _databaseConfigIdController =
      TextEditingController();
  final TextEditingController _backupFolderController = TextEditingController();
  final TextEditingController _intervalMinutesController =
      TextEditingController(text: '60');

  ScheduleType _scheduleType = ScheduleType.daily;
  DatabaseType _databaseType = DatabaseType.sqlServer;
  int _hour = 2;
  int _minute = 0;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    if (template != null) {
      _databaseConfigIdController.text = template.databaseConfigId;
      _databaseType = template.databaseType;
      _backupFolderController.text = template.backupFolder;
      _scheduleType = scheduleTypeFromString(template.scheduleType);
      _parseScheduleConfig(template.scheduleConfig);
    } else {
      _backupFolderController.text = _defaultBackupFolder();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _databaseConfigIdController.dispose();
    _backupFolderController.dispose();
    _intervalMinutesController.dispose();
    super.dispose();
  }

  String _defaultBackupFolder() {
    final systemTemp =
        Platform.environment['TEMP'] ??
        Platform.environment['TMP'] ??
        r'C:\Temp';
    return '$systemTemp\\BackupDatabase';
  }

  void _parseScheduleConfig(String configJson) {
    try {
      final config = jsonDecode(configJson) as Map<String, dynamic>;
      switch (_scheduleType) {
        case ScheduleType.daily:
        case ScheduleType.weekly:
        case ScheduleType.monthly:
          _hour = (config['hour'] as int?) ?? _hour;
          _minute = (config['minute'] as int?) ?? _minute;
        case ScheduleType.interval:
          final minutes = (config['intervalMinutes'] as int?) ?? 60;
          _intervalMinutesController.text = minutes.toString();
      }
    } on Object {
      // Mantém defaults do dialogo.
    }
  }

  String _buildScheduleConfigJson() {
    switch (_scheduleType) {
      case ScheduleType.daily:
        return jsonEncode({'hour': _hour, 'minute': _minute});
      case ScheduleType.weekly:
        return jsonEncode({
          'daysOfWeek': [1],
          'hour': _hour,
          'minute': _minute,
        });
      case ScheduleType.monthly:
        return jsonEncode({
          'daysOfMonth': [1],
          'hour': _hour,
          'minute': _minute,
        });
      case ScheduleType.interval:
        final minutes =
            int.tryParse(_intervalMinutesController.text.trim()) ?? 60;
        return jsonEncode({'intervalMinutes': minutes});
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _validationError = 'Informe o nome do agendamento.');
      return;
    }
    final databaseConfigId = _databaseConfigIdController.text.trim();
    if (databaseConfigId.isEmpty) {
      setState(
        () => _validationError = 'Informe o ID da configuração de banco.',
      );
      return;
    }
    final backupFolder = _backupFolderController.text.trim();
    if (backupFolder.isEmpty) {
      setState(() => _validationError = 'Informe a pasta de backup.');
      return;
    }

    final schedule = Schedule(
      name: name,
      databaseConfigId: databaseConfigId,
      databaseType: _databaseType,
      scheduleType: _scheduleType.toValue(),
      scheduleConfig: _buildScheduleConfigJson(),
      destinationIds: widget.template?.destinationIds ?? const <String>[],
      backupFolder: backupFolder,
    );
    Navigator.of(context).pop(schedule);
  }

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);
    final showTimeFields = _scheduleType != ScheduleType.interval;

    return ContentDialog(
      title: Text(
        appLocaleString(
          context,
          'Novo agendamento remoto',
          'New remote schedule',
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_validationError != null) ...[
                InfoBar(
                  title: const Text('Validação'),
                  content: Text(_validationError!),
                  severity: InfoBarSeverity.warning,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextBox(
                controller: _nameController,
                placeholder: appLocaleString(
                  context,
                  'Nome do agendamento',
                  'Schedule name',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ComboBox<ScheduleType>(
                placeholder: Text(
                  appLocaleString(context, 'Tipo', 'Type'),
                ),
                value: _scheduleType,
                items: ScheduleType.values
                    .map(
                      (type) => ComboBoxItem(
                        value: type,
                        child: Text(texts.scheduleTypeName(type)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _scheduleType = value);
                },
              ),
              if (showTimeFields) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  appLocaleString(context, 'Horário', 'Time'),
                  style: FluentTheme.of(context).typography.bodyStrong,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: NumberBox(
                        value: _hour.toDouble(),
                        min: 0,
                        max: 23,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _hour = value.round());
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: NumberBox(
                        value: _minute.toDouble(),
                        min: 0,
                        max: 59,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _minute = value.round());
                        },
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.md),
                TextBox(
                  controller: _intervalMinutesController,
                  placeholder: appLocaleString(
                    context,
                    'Intervalo (minutos)',
                    'Interval (minutes)',
                  ),
                ),
              ],
              if (widget.template == null) ...[
                const SizedBox(height: AppSpacing.md),
                TextBox(
                  controller: _databaseConfigIdController,
                  placeholder: appLocaleString(
                    context,
                    'ID da configuração de banco',
                    'Database config ID',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ComboBox<DatabaseType>(
                  value: _databaseType,
                  items: DatabaseType.values
                      .map(
                        (type) => ComboBoxItem(
                          value: type,
                          child: Text(
                            DatabaseTypeMetadata.of(type).chipLabel,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _databaseType = value);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextBox(
                  controller: _backupFolderController,
                  placeholder: appLocaleString(
                    context,
                    'Pasta de backup no servidor',
                    'Backup folder on server',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appLocaleString(context, 'Cancelar', 'Cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(appLocaleString(context, 'Criar', 'Create')),
        ),
      ],
    );
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

class _BackupProgressCard extends StatelessWidget {
  const _BackupProgressCard({
    required this.provider,
    required this.onCancel,
  });

  final RemoteSchedulesProvider provider;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final schedule = provider.schedules.firstWhere(
      (s) => s.id == provider.executingScheduleId,
      orElse: () => provider.schedules.first,
    );
    final backupError = provider.error;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const ProgressRing(strokeWidth: 2),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appLocaleString(
                          context,
                          'Executando backup no servidor',
                          'Running backup on server',
                        ),
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        schedule.name,
                        style: FluentTheme.of(context).typography.bodyStrong,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (provider.activeRunId != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SelectableText(
                appLocaleString(
                  context,
                  'Execução: ${provider.activeRunId}',
                  'Run: ${provider.activeRunId}',
                ),
                style: FluentTheme.of(context).typography.caption,
              ),
            ],
            if (provider.backupStep != null) ...[
              const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              Text(
                provider.backupStep!,
                style: FluentTheme.of(context).typography.caption,
              ),
            ],
            if (provider.backupMessage != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                provider.backupMessage!,
                style: FluentTheme.of(context).typography.body,
              ),
            ],
            if (backupError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SelectableText.rich(
                TextSpan(
                  text: appLocaleString(context, 'Erro: ', 'Error: '),
                  children: [
                    TextSpan(
                      text: backupError,
                      style: FluentTheme.of(context).typography.body?.copyWith(
                        color: context.colors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (provider.backupProgress != null) ...[
              const SizedBox(height: AppSpacing.sm),
              ProgressBar(
                value: provider.backupProgress! * 100,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: onCancel,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.cancel, size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    appLocaleString(
                      context,
                      'Cancelar backup',
                      'Cancel backup',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerExecutionQueueCard extends StatelessWidget {
  const _ServerExecutionQueueCard({
    required this.provider,
    required this.scheduleNameFor,
  });

  final RemoteSchedulesProvider provider;
  final String Function(RemoteSchedulesProvider provider, String scheduleId)
  scheduleNameFor;

  @override
  Widget build(BuildContext context) {
    final queueError = provider.executionQueueError;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appLocaleString(
                      context,
                      'Fila no servidor',
                      'Server queue',
                    ),
                    style: FluentTheme.of(context).typography.subtitle,
                  ),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.refresh),
                  onPressed: provider.isLoadingExecutionQueue
                      ? null
                      : () => unawaited(provider.loadExecutionQueue()),
                ),
              ],
            ),
            if (queueError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SelectableText.rich(
                TextSpan(
                  text: queueError,
                  style: FluentTheme.of(context).typography.body?.copyWith(
                    color: context.colors.danger,
                  ),
                ),
              ),
            ] else if (provider.isLoadingExecutionQueue &&
                provider.executionQueue.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: ProgressRing(strokeWidth: 2),
              )
            else if (provider.executionQueue.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  appLocaleString(
                    context,
                    'Nenhum backup aguardando na fila do servidor.',
                    'No backups waiting in the server queue.',
                  ),
                  style: FluentTheme.of(context).typography.body,
                ),
              )
            else
              ...provider.executionQueue.map(
                (item) => _QueuedExecutionRow(
                  item: item,
                  scheduleLabel: scheduleNameFor(provider, item.scheduleId),
                  onCancel: () =>
                      _onCancelQueued(context, provider, item.runId),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onCancelQueued(
    BuildContext context,
    RemoteSchedulesProvider provider,
    String runId,
  ) async {
    final success = await provider.cancelQueuedRemoteBackup(runId);
    if (!context.mounted) return;
    if (success) {
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Item removido da fila do servidor.',
            'Item removed from server queue.',
          ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao cancelar item da fila.',
        ),
      );
    }
  }
}

class _QueuedExecutionRow extends StatelessWidget {
  const _QueuedExecutionRow({
    required this.item,
    required this.scheduleLabel,
    required this.onCancel,
  });

  final QueuedExecution item;
  final String scheduleLabel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scheduleLabel,
                  style: FluentTheme.of(context).typography.bodyStrong,
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  appLocaleString(
                    context,
                    'Agendamento: ${item.scheduleId} · Posição ${item.queuedPosition}',
                    'Schedule: ${item.scheduleId} · Position ${item.queuedPosition}',
                  ),
                  style: FluentTheme.of(context).typography.caption,
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  appLocaleString(
                    context,
                    'Execução: ${item.runId}',
                    'Run: ${item.runId}',
                  ),
                  style: FluentTheme.of(context).typography.caption,
                ),
              ],
            ),
          ),
          Button(
            onPressed: onCancel,
            child: Text(
              appLocaleString(context, 'Cancelar', 'Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}
