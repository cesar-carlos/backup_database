import 'dart:async';

import 'package:backup_database/application/dtos/remote/queued_execution_view.dart';
import 'package:backup_database/application/dtos/remote/remote_dto_mappers.dart';
import 'package:backup_database/application/dtos/remote/remote_preflight_view.dart';
import 'package:backup_database/application/dtos/remote/run_diagnostics_view.dart';
import 'package:backup_database/application/providers/remote/pending_remote_run_store.dart';
import 'package:backup_database/application/providers/remote/remote_run_resume_service.dart';
import 'package:backup_database/application/providers/remote/remote_schedule_execution_coordinator.dart';
import 'package:backup_database/application/providers/remote/remote_schedules_run_session.dart';
import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/errors/failure.dart'
    show Failure, failureUserMessage;
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/utils/error_mapper.dart'
    show mapExceptionToMessage;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/connection_status.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';
import 'package:backup_database/infrastructure/protocol/queue_events.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

export 'package:backup_database/application/providers/remote/remote_schedule_execution_coordinator.dart'
    show EnsureServerHealthyForBackup;

enum RemotePreflightUiAction { proceed, showDialog, notApplicable }

class RemotePreflightRunResult {
  const RemotePreflightRunResult({
    required this.action,
    this.preflight,
    this.errorMessage,
  });

  final RemotePreflightUiAction action;
  final RemotePreflightView? preflight;
  final String? errorMessage;

  bool get isBlocked => preflight?.isBlocked ?? false;

  bool get hasWarningsOnly =>
      preflight != null && preflight!.hasWarnings && !preflight!.isBlocked;
}

class RemoteSchedulesProvider extends ChangeNotifier {
  RemoteSchedulesProvider(
    this._connectionManager, {
    this._transferProvider,
    TempDirectoryService? tempDirectoryService,
    EnsureServerHealthyForBackup? ensureServerHealthy,
    IMachineSettingsRepository? machineSettings,
  }) : _tempDirectoryService =
           tempDirectoryService ?? getIt<TempDirectoryService>(),
       _machineSettings =
           machineSettings ??
           (getIt.isRegistered<IMachineSettingsRepository>()
               ? getIt<IMachineSettingsRepository>()
               : null) {
    final pendingRunStore = PendingRemoteRunStore(_machineSettings);
    _session = RemoteSchedulesRunSession(
      notifyListeners: notifyListeners,
      pendingRunStore: pendingRunStore,
    );
    final ensureHealthy =
        ensureServerHealthy ??
        (() => _refreshServerHealthViaConnectionManager(_connectionManager));
    _execution = RemoteScheduleExecutionCoordinator(
      connectionManager: _connectionManager,
      session: _session,
      pendingRunStore: pendingRunStore,
      tempDirectoryService: _tempDirectoryService,
      ensureServerHealthy: ensureHealthy,
      loadExecutionQueue: loadExecutionQueue,
      transferProvider: _transferProvider,
    );
    _resume = RemoteRunResumeService(
      connectionManager: _connectionManager,
      session: _session,
      execution: _execution,
    );
    _pendingRunStore = pendingRunStore;
    _listenToConnectionStatus();
    _queueEventsSubscription = _connectionManager.queueEvents.listen(
      _onQueueEvent,
    );
    unawaited(_restorePendingRemoteRunFromDisk());
  }

  final ConnectionManager _connectionManager;
  final IMachineSettingsRepository? _machineSettings;
  final RemoteFileTransferProvider? _transferProvider;
  final TempDirectoryService _tempDirectoryService;

  late final RemoteSchedulesRunSession _session;
  late final RemoteScheduleExecutionCoordinator _execution;
  late final RemoteRunResumeService _resume;
  late final PendingRemoteRunStore _pendingRunStore;

  static Future<bool> _refreshServerHealthViaConnectionManager(
    ConnectionManager manager,
  ) async {
    final result = await manager.getServerHealth();
    return result.fold(
      (health) => health.isOk,
      (_) => true,
    );
  }

  StreamSubscription<ConnectionStatus>? _statusSubscription;
  StreamSubscription<QueueEvent>? _queueEventsSubscription;

  List<Schedule> _schedules = [];
  bool _isLoading = false;
  bool _isUpdating = false;
  String? _updatingScheduleId;

  List<QueuedExecutionView> _executionQueue = [];
  bool _isLoadingExecutionQueue = false;
  String? _executionQueueError;

  List<Schedule> get schedules => _schedules;
  bool get isLoading => _isLoading;
  bool get isUpdating => _isUpdating;
  bool get isExecuting => _session.isExecuting;
  String? get error => _session.error;
  String? get lastErrorCode => _session.lastErrorCode;
  bool get isConnected => _connectionManager.isConnected;
  String? get updatingScheduleId => _updatingScheduleId;
  String? get executingScheduleId => _session.executingScheduleId;
  String? get activeRunId => _session.activeRunId;
  String? get backupStep => _session.backupStep;
  String? get backupMessage => _session.backupMessage;
  double? get backupProgress => _session.backupProgress;
  String? get transferStep => _session.transferStep;
  String? get transferMessage => _session.transferMessage;
  double? get transferProgress => _session.transferProgress;
  bool get isTransferringFile => _session.isTransferringFile;
  List<QueuedExecutionView> get executionQueue => _executionQueue;
  bool get isLoadingExecutionQueue => _isLoadingExecutionQueue;
  String? get executionQueueError => _executionQueueError;

  Future<void> loadSchedules() async {
    if (!_connectionManager.isConnected) {
      _session.error = 'Conecte-se a um servidor para ver os agendamentos.';
      _session.lastErrorCode = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _session.error = null;
    _session.lastErrorCode = null;
    notifyListeners();

    final result = await _connectionManager.listSchedules();

    result.fold(
      (list) {
        _schedules = list;
        _isLoading = false;
        _session.lastErrorCode = null;
      },
      (exception) {
        _session.error = mapExceptionToMessage(exception);
        _session.lastErrorCode = exception is Failure ? exception.code : null;
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<void> loadExecutionQueue() async {
    if (!_connectionManager.isConnected ||
        !_connectionManager.isExecutionQueueSupported) {
      _executionQueue = [];
      _executionQueueError = null;
      _isLoadingExecutionQueue = false;
      notifyListeners();
      return;
    }

    _isLoadingExecutionQueue = true;
    _executionQueueError = null;
    notifyListeners();

    final result = await _connectionManager.getExecutionQueue();
    result.fold(
      (snapshot) {
        _executionQueue = snapshot.queue
            .map(queuedExecutionViewFromProtocol)
            .toList();
        _isLoadingExecutionQueue = false;
        _executionQueueError = null;
      },
      (exception) {
        _executionQueueError = mapExceptionToMessage(exception);
        _isLoadingExecutionQueue = false;
      },
    );
    notifyListeners();
  }

  Future<bool> createRemoteSchedule(Schedule schedule) async {
    if (!_connectionManager.isConnected) {
      _session.error = 'Conecte-se a um servidor para criar agendamentos.';
      _session.lastErrorCode = null;
      notifyListeners();
      return false;
    }

    _isUpdating = true;
    _updatingScheduleId = null;
    _session.error = null;
    _session.lastErrorCode = null;
    notifyListeners();

    final result = await _connectionManager.createRemoteSchedule(
      schedule: schedule,
      idempotencyKey: const Uuid().v4(),
    );

    return result.fold(
      (_) async {
        _session.error = null;
        _session.lastErrorCode = null;
        _isUpdating = false;
        notifyListeners();
        await _reloadSchedulesAndQueue();
        return true;
      },
      (exception) {
        _session.error = failureUserMessage(exception);
        _session.lastErrorCode = exception is Failure ? exception.code : null;
        _isUpdating = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> deleteRemoteSchedule(String scheduleId) async {
    if (!_connectionManager.isConnected) {
      _session.error = 'Conecte-se a um servidor para excluir agendamentos.';
      _session.lastErrorCode = null;
      notifyListeners();
      return false;
    }
    if (scheduleId.isEmpty) {
      _session.error = 'Identificador de agendamento inválido.';
      _session.lastErrorCode = null;
      notifyListeners();
      return false;
    }

    _isUpdating = true;
    _updatingScheduleId = scheduleId;
    _session.error = null;
    _session.lastErrorCode = null;
    notifyListeners();

    final result = await _connectionManager.deleteRemoteSchedule(
      scheduleId: scheduleId,
      idempotencyKey: const Uuid().v4(),
    );

    return result.fold(
      (_) async {
        _schedules = _schedules.where((s) => s.id != scheduleId).toList();
        _session.error = null;
        _session.lastErrorCode = null;
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        await _reloadSchedulesAndQueue();
        return true;
      },
      (exception) {
        _session.error = failureUserMessage(exception);
        _session.lastErrorCode = exception is Failure ? exception.code : null;
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> setRemoteSchedulePaused({
    required String scheduleId,
    required bool paused,
  }) async {
    if (!_connectionManager.isConnected) {
      _session.error = paused
          ? 'Conecte-se a um servidor para pausar agendamentos.'
          : 'Conecte-se a um servidor para retomar agendamentos.';
      _session.lastErrorCode = null;
      notifyListeners();
      return false;
    }
    if (scheduleId.isEmpty) {
      _session.error = 'Identificador de agendamento inválido.';
      _session.lastErrorCode = null;
      notifyListeners();
      return false;
    }

    _isUpdating = true;
    _updatingScheduleId = scheduleId;
    _session.error = null;
    _session.lastErrorCode = null;
    notifyListeners();

    final idempotencyKey = const Uuid().v4();
    final result = paused
        ? await _connectionManager.pauseRemoteSchedule(
            scheduleId: scheduleId,
            idempotencyKey: idempotencyKey,
          )
        : await _connectionManager.resumeRemoteSchedule(
            scheduleId: scheduleId,
            idempotencyKey: idempotencyKey,
          );

    return result.fold(
      (mutation) async {
        final snapshot = mutation.schedule;
        if (snapshot != null) {
          final index = _schedules.indexWhere((s) => s.id == snapshot.id);
          if (index >= 0) {
            _schedules = List<Schedule>.from(_schedules)..[index] = snapshot;
          }
        } else {
          final index = _schedules.indexWhere((s) => s.id == scheduleId);
          if (index >= 0) {
            _schedules = List<Schedule>.from(_schedules)
              ..[index] = _schedules[index].copyWith(enabled: !paused);
          }
        }
        _session.error = null;
        _session.lastErrorCode = null;
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        await _reloadSchedulesAndQueue();
        return true;
      },
      (exception) {
        _session.error = failureUserMessage(exception);
        _session.lastErrorCode = exception is Failure ? exception.code : null;
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        return false;
      },
    );
  }

  Future<void> _reloadSchedulesAndQueue() async {
    await loadSchedules();
    if (_connectionManager.isExecutionQueueSupported) {
      await loadExecutionQueue();
    }
  }

  Future<bool> updateSchedule(Schedule schedule) async {
    if (!_connectionManager.isConnected) {
      _session.error = 'Conecte-se a um servidor para atualizar agendamentos.';
      _session.lastErrorCode = null;
      notifyListeners();
      return false;
    }

    _isUpdating = true;
    _updatingScheduleId = schedule.id;
    _session.error = null;
    _session.lastErrorCode = null;
    notifyListeners();

    final result = await _connectionManager.updateSchedule(schedule);

    return result.fold(
      (updated) {
        final index = _schedules.indexWhere((s) => s.id == updated.id);
        if (index >= 0) {
          _schedules = List<Schedule>.from(_schedules)..[index] = updated;
        }
        _session.error = null;
        _session.lastErrorCode = null;
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        return true;
      },
      (exception) {
        _session.error = mapExceptionToMessage(exception);
        _session.lastErrorCode = exception is Failure ? exception.code : null;
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        return false;
      },
    );
  }

  Future<RemotePreflightRunResult> runPreflightForSchedule() async {
    if (!_connectionManager.isConnected) {
      return const RemotePreflightRunResult(
        action: RemotePreflightUiAction.notApplicable,
        errorMessage: 'Conecte-se a um servidor para executar agendamentos.',
      );
    }
    if (!_connectionManager.isRunIdSupported) {
      return const RemotePreflightRunResult(
        action: RemotePreflightUiAction.notApplicable,
      );
    }

    final result = await _connectionManager.validateServerBackupPrerequisites();
    return result.fold(
      (preflight) {
        if (preflight.isBlocked || preflight.hasWarnings) {
          return RemotePreflightRunResult(
            action: RemotePreflightUiAction.showDialog,
            preflight: remotePreflightViewFromProtocol(preflight),
          );
        }
        return RemotePreflightRunResult(
          action: RemotePreflightUiAction.proceed,
          preflight: remotePreflightViewFromProtocol(preflight),
        );
      },
      (exception) {
        LoggerService.warning('Preflight remoto falhou: $exception');
        return const RemotePreflightRunResult(
          action: RemotePreflightUiAction.proceed,
        );
      },
    );
  }

  Future<RunDiagnosticsView> loadRunDiagnostics(
    String runId, {
    bool includeErrorDetails = true,
    int maxLogLines = 500,
  }) async {
    final logsResult = await _connectionManager.getRunLogs(
      runId: runId,
      maxLines: maxLogLines,
    );
    final detailsResult = includeErrorDetails
        ? await _connectionManager.getRunErrorDetails(runId: runId)
        : null;

    RunDiagnosticsLogsView? logs;
    String? logsError;
    logsResult.fold(
      (value) => logs = runDiagnosticsLogsFromProtocol(value),
      (failure) => logsError = failureUserMessage(failure),
    );

    RunDiagnosticsErrorView? errorDetails;
    String? errorDetailsError;
    if (detailsResult != null) {
      detailsResult.fold(
        (value) => errorDetails = runDiagnosticsErrorFromProtocol(value),
        (failure) => errorDetailsError = failureUserMessage(failure),
      );
    }

    return RunDiagnosticsView(
      logs: logs,
      logsError: logsError,
      errorDetails: errorDetails,
      errorDetailsError: errorDetailsError,
    );
  }

  Future<bool> executeSchedule(
    String scheduleId, {
    bool skipPreflightCheck = false,
  }) {
    return _execution.executeSchedule(
      scheduleId,
      skipPreflightCheck: skipPreflightCheck,
    );
  }

  Future<void> tryResumeExecutionAfterReconnect() {
    return _resume.tryResumeExecutionAfterReconnect();
  }

  Future<bool> cancelQueuedRemoteBackup(String runId) async {
    if (!_connectionManager.isConnected) {
      _session.error = 'Conecte-se a um servidor para cancelar itens da fila.';
      _session.lastErrorCode = null;
      notifyListeners();
      return false;
    }
    if (!_connectionManager.isExecutionQueueSupported) {
      _session.error = 'Servidor não suporta cancelamento na fila remota.';
      _session.lastErrorCode = null;
      notifyListeners();
      return false;
    }
    if (runId.isEmpty) {
      _session.error = 'Identificador de execução inválido.';
      _session.lastErrorCode = null;
      notifyListeners();
      return false;
    }

    final result = await _connectionManager.cancelQueuedRemoteBackup(
      runId: runId,
    );

    return result.fold(
      (cancelResult) async {
        if (cancelResult.isCancelled) {
          await loadExecutionQueue();
          return true;
        }
        _session.error =
            cancelResult.message ?? 'Item não encontrado na fila do servidor.';
        _session.lastErrorCode = null;
        notifyListeners();
        return false;
      },
      (exception) {
        _session.error = mapExceptionToMessage(exception);
        _session.lastErrorCode = exception is Failure ? exception.code : null;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> cancelSchedule() => _execution.cancelSchedule();

  void clearError() {
    _session.error = null;
    _session.lastErrorCode = null;
    notifyListeners();
  }

  void clearExecutionStateOnDisconnect() {
    _session.clearExecutionStateOnDisconnect();
  }

  void _onQueueEvent(QueueEvent event) {
    if (_session.activeRunId == null || event.runId != _session.activeRunId) {
      return;
    }
    if (event.isQueued) {
      _session.backupStep = 'Na fila';
      _session.backupMessage =
          event.message ??
          (event.queuePosition != null
              ? 'Posição ${event.queuePosition} na fila do servidor'
              : 'Aguardando slot no servidor');
      _session.backupProgress ??= 0;
      notifyListeners();
      return;
    }
    if (event.isStarted) {
      _session.backupStep = 'Em execução';
      _session.backupMessage = event.message ?? 'Backup iniciado no servidor';
      notifyListeners();
    }
  }

  Future<void> _restorePendingRemoteRunFromDisk() async {
    final snapshot = await _pendingRunStore.restore();
    if (snapshot == null) return;
    _session.applyRestoredSnapshot(snapshot);
    LoggerService.info(
      '[remote_schedules] Snapshot pré-restart restaurado: '
      'runId=${snapshot.runId}, scheduleId=${snapshot.scheduleId}',
    );
  }

  void _listenToConnectionStatus() {
    final previous = _statusSubscription;
    if (previous != null) {
      unawaited(previous.cancel());
    }
    _statusSubscription = _connectionManager.statusStream?.listen(
      _onConnectionStatusChanged,
    );
  }

  void _onConnectionStatusChanged(ConnectionStatus status) {
    final isTerminal =
        status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error ||
        status == ConnectionStatus.authenticationFailed;
    if (isTerminal) {
      clearExecutionStateOnDisconnect();
    }
  }

  @override
  void dispose() {
    if (_statusSubscription != null) {
      unawaited(_statusSubscription!.cancel());
      _statusSubscription = null;
    }
    if (_queueEventsSubscription != null) {
      unawaited(_queueEventsSubscription!.cancel());
      _queueEventsSubscription = null;
    }
    super.dispose();
  }
}
