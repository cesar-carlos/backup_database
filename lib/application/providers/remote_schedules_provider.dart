import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/core/constants/socket_config.dart';
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
import 'package:backup_database/infrastructure/protocol/diagnostics_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/protocol/queue_events.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:uuid/uuid.dart';

typedef EnsureServerHealthyForBackup = Future<bool> Function();

enum RemotePreflightUiAction { proceed, showDialog, notApplicable }

class RemotePreflightRunResult {
  const RemotePreflightRunResult({
    required this.action,
    this.preflight,
    this.errorMessage,
  });

  final RemotePreflightUiAction action;
  final PreflightResult? preflight;
  final String? errorMessage;

  bool get isBlocked => preflight?.isBlocked ?? false;

  bool get hasWarningsOnly =>
      preflight != null && preflight!.hasWarnings && !preflight!.isBlocked;
}

class RemoteSchedulesProvider extends ChangeNotifier {
  RemoteSchedulesProvider(
    this._connectionManager, {
    RemoteFileTransferProvider? transferProvider,
    TempDirectoryService? tempDirectoryService,
    EnsureServerHealthyForBackup? ensureServerHealthy,
    IMachineSettingsRepository? machineSettings,
  }) : _transferProvider = transferProvider,
       _tempDirectoryService =
           tempDirectoryService ?? getIt<TempDirectoryService>(),
       _machineSettings =
           machineSettings ??
           (getIt.isRegistered<IMachineSettingsRepository>()
               ? getIt<IMachineSettingsRepository>()
               : null),
       _ensureServerHealthy =
           ensureServerHealthy ??
           (() =>
               _refreshServerHealthViaConnectionManager(_connectionManager)) {
    _listenToConnectionStatus();
    _queueEventsSubscription = _connectionManager.queueEvents.listen(
      _onQueueEvent,
    );
    // §audit-2026-05-28 wave 3 (P2): tenta restaurar estado de run
    // pendente do disco. Não bloqueia o construtor; quando carregar,
    // a primeira `ConnectionStatus.connected` dispara o resume.
    unawaited(_restorePendingRemoteRunFromDisk());
  }

  final ConnectionManager _connectionManager;
  final EnsureServerHealthyForBackup _ensureServerHealthy;
  final IMachineSettingsRepository? _machineSettings;

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
  final RemoteFileTransferProvider? _transferProvider;
  final TempDirectoryService _tempDirectoryService;

  List<Schedule> _schedules = [];
  bool _isLoading = false;
  bool _isUpdating = false;
  bool _isExecuting = false;
  String? _error;
  String? _lastErrorCode;
  String? _updatingScheduleId;
  String? _executingScheduleId;
  String? _activeRunId;
  bool _disconnectedDuringRun = false;

  /// §audit-2026-05-28 wave 2 (P1): guarda contra dupla execução do
  /// resume após reconnect. Antes, tanto o
  /// `ServerConnectionProvider._listenToConnectionStatus` quanto o
  /// `RemoteSchedulesPage._onConnectionChanged` chamavam este método
  /// — se a página estivesse aberta no momento da reconexão, os dois
  /// fluxos rodavam em paralelo (`getExecutionStatus`,
  /// `waitForRemoteBackupCompletion`, `_finishBackupAndDownload`),
  /// disparando downloads duplicados do mesmo `runId`.
  ///
  /// O `ServerConnectionProvider` é agora o **único owner** desta
  /// chamada, mas mantemos a flag como defesa em profundidade
  /// (re-entrância acidental por callbacks de UI futuros).
  bool _isResumingAfterReconnect = false;

  String? _backupStep;
  String? _backupMessage;
  double? _backupProgress;

  String? _transferStep;
  String? _transferMessage;
  double? _transferProgress;
  bool _isTransferringFile = false;

  List<QueuedExecution> _executionQueue = [];
  bool _isLoadingExecutionQueue = false;
  String? _executionQueueError;

  List<Schedule> get schedules => _schedules;
  bool get isLoading => _isLoading;
  bool get isUpdating => _isUpdating;
  bool get isExecuting => _isExecuting;
  String? get error => _error;
  String? get lastErrorCode => _lastErrorCode;
  bool get isConnected => _connectionManager.isConnected;
  String? get updatingScheduleId => _updatingScheduleId;
  String? get executingScheduleId => _executingScheduleId;
  String? get activeRunId => _activeRunId;
  String? get backupStep => _backupStep;
  String? get backupMessage => _backupMessage;
  double? get backupProgress => _backupProgress;
  String? get transferStep => _transferStep;
  String? get transferMessage => _transferMessage;
  double? get transferProgress => _transferProgress;
  bool get isTransferringFile => _isTransferringFile;
  List<QueuedExecution> get executionQueue => _executionQueue;
  bool get isLoadingExecutionQueue => _isLoadingExecutionQueue;
  String? get executionQueueError => _executionQueueError;

  Future<void> loadSchedules() async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para ver os agendamentos.';
      _lastErrorCode = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    _lastErrorCode = null;
    notifyListeners();

    final result = await _connectionManager.listSchedules();

    result.fold(
      (list) {
        _schedules = list;
        _isLoading = false;
        _lastErrorCode = null;
      },
      (exception) {
        _error = mapExceptionToMessage(exception);
        _lastErrorCode = exception is Failure ? exception.code : null;
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
        _executionQueue = List<QueuedExecution>.from(snapshot.queue);
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
      _error = 'Conecte-se a um servidor para criar agendamentos.';
      _lastErrorCode = null;
      notifyListeners();
      return false;
    }

    _isUpdating = true;
    _updatingScheduleId = null;
    _error = null;
    _lastErrorCode = null;
    notifyListeners();

    final result = await _connectionManager.createRemoteSchedule(
      schedule: schedule,
      idempotencyKey: const Uuid().v4(),
    );

    return result.fold(
      (_) async {
        _error = null;
        _lastErrorCode = null;
        _isUpdating = false;
        notifyListeners();
        await _reloadSchedulesAndQueue();
        return true;
      },
      (exception) {
        _error = failureUserMessage(exception);
        _lastErrorCode = exception is Failure ? exception.code : null;
        _isUpdating = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> deleteRemoteSchedule(String scheduleId) async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para excluir agendamentos.';
      _lastErrorCode = null;
      notifyListeners();
      return false;
    }
    if (scheduleId.isEmpty) {
      _error = 'Identificador de agendamento inválido.';
      _lastErrorCode = null;
      notifyListeners();
      return false;
    }

    _isUpdating = true;
    _updatingScheduleId = scheduleId;
    _error = null;
    _lastErrorCode = null;
    notifyListeners();

    final result = await _connectionManager.deleteRemoteSchedule(
      scheduleId: scheduleId,
      idempotencyKey: const Uuid().v4(),
    );

    return result.fold(
      (_) async {
        _schedules = _schedules.where((s) => s.id != scheduleId).toList();
        _error = null;
        _lastErrorCode = null;
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        await _reloadSchedulesAndQueue();
        return true;
      },
      (exception) {
        _error = failureUserMessage(exception);
        _lastErrorCode = exception is Failure ? exception.code : null;
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
      _error = paused
          ? 'Conecte-se a um servidor para pausar agendamentos.'
          : 'Conecte-se a um servidor para retomar agendamentos.';
      _lastErrorCode = null;
      notifyListeners();
      return false;
    }
    if (scheduleId.isEmpty) {
      _error = 'Identificador de agendamento inválido.';
      _lastErrorCode = null;
      notifyListeners();
      return false;
    }

    _isUpdating = true;
    _updatingScheduleId = scheduleId;
    _error = null;
    _lastErrorCode = null;
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
        _error = null;
        _lastErrorCode = null;
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        await _reloadSchedulesAndQueue();
        return true;
      },
      (exception) {
        _error = failureUserMessage(exception);
        _lastErrorCode = exception is Failure ? exception.code : null;
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
      _error = 'Conecte-se a um servidor para atualizar agendamentos.';
      _lastErrorCode = null;
      notifyListeners();
      return false;
    }

    _isUpdating = true;
    _updatingScheduleId = schedule.id;
    _error = null;
    _lastErrorCode = null;
    notifyListeners();

    final result = await _connectionManager.updateSchedule(schedule);

    return result.fold(
      (updated) {
        final index = _schedules.indexWhere((s) => s.id == updated.id);
        if (index >= 0) {
          _schedules = List<Schedule>.from(_schedules)..[index] = updated;
        }
        _error = null;
        _lastErrorCode = null;
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        return true;
      },
      (exception) {
        _error = mapExceptionToMessage(exception);
        _lastErrorCode = exception is Failure ? exception.code : null;
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
            preflight: preflight,
          );
        }
        return RemotePreflightRunResult(
          action: RemotePreflightUiAction.proceed,
          preflight: preflight,
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

  Future<bool> executeSchedule(
    String scheduleId, {
    bool skipPreflightCheck = false,
  }) async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para executar agendamentos.';
      _lastErrorCode = null;
      notifyListeners();
      return false;
    }

    if (_connectionManager.isRunIdSupported) {
      final isHealthy = await _ensureServerHealthy();
      if (!isHealthy) {
        _error =
            'Servidor indisponível ou com problemas de saúde. '
            'Atualize o status da conexão e tente novamente.';
        _lastErrorCode = null;
        notifyListeners();
        return false;
      }
    }

    _beginExecution(scheduleId);

    if (_connectionManager.isRunIdSupported && !skipPreflightCheck) {
      final preflightOk = await _runServerPreflightGate();
      if (!preflightOk) {
        return false;
      }
    }

    final idempotencyKey = const Uuid().v4();
    final backupResult = _connectionManager.isRunIdSupported
        ? await _connectionManager.executeRemoteBackup(
            scheduleId: scheduleId,
            idempotencyKey: idempotencyKey,
            queueIfBusy: _connectionManager.isExecutionQueueSupported,
            onProgress: _onBackupProgress,
            onRunIdKnown: (runId) {
              _activeRunId = runId;
              // §audit-2026-05-28 wave 3 (P2): persiste IMEDIATAMENTE
              // ao saber o runId. Crash / auto-update entre aqui e o
              // término do backup continua recuperável: no próximo
              // boot lemos esse JSON e o `tryResumeExecutionAfterReconnect`
              // já existente cuida do resto.
              unawaited(
                _persistPendingRemoteRunSnapshot(
                  runId: runId,
                  scheduleId: scheduleId,
                ),
              );
              notifyListeners();
            },
          )
        // Fallback consciente para servidor `v1` sem `supportsRunId`.
        // O caminho deprecado ainda existe para compat de janela; quando o
        // suporte a servidor v1 for removido, este else cai junto.
        // ignore: deprecated_member_use_from_same_package
        : await _connectionManager.executeSchedule(
            scheduleId,
            onProgress: _onBackupProgress,
          );

    final finished = await backupResult.fold(
      (backupPath) async => _finishBackupAndDownload(
        scheduleId: scheduleId,
        backupPath: backupPath,
        runId: _activeRunId,
      ),
      (exception) async {
        if (_shouldPreserveStateAfterDisconnectFailure(exception)) {
          _isExecuting = false;
          _disconnectedDuringRun = true;
          _error = _connectionLostMessage;
          _lastErrorCode = null;
          notifyListeners();
          return false;
        }
        _resetExecutionState(
          error: mapExceptionToMessage(exception),
          errorCode: exception is Failure ? exception.code : null,
        );
        return false;
      },
    );
    if (_connectionManager.isExecutionQueueSupported) {
      unawaited(loadExecutionQueue());
    }
    return finished;
  }

  bool _shouldPreserveStateAfterDisconnectFailure(Object failure) {
    if (_activeRunId == null) return false;
    if (_disconnectedDuringRun) return true;
    if (failure is StateError && failure.message == 'Disconnected') {
      return true;
    }
    final message = mapExceptionToMessage(failure);
    if (message.contains('Disconnected during backup') ||
        message.contains('Conexão encerrada') ||
        message.contains('durante o backup') ||
        message.contains('desconectado do servidor')) {
      return true;
    }
    final raw = failureUserMessage(failure, fallback: '');
    return raw.contains('Disconnected during backup') ||
        raw.contains('Conexão encerrada') ||
        (raw.contains('Disconnected') && raw.contains('backup'));
  }

  void _beginExecution(String scheduleId) {
    _isExecuting = true;
    _executingScheduleId = scheduleId;
    _activeRunId = null;
    _disconnectedDuringRun = false;
    _error = null;
    _lastErrorCode = null;
    _backupStep = 'Iniciando';
    _backupMessage = 'Solicitando backup no servidor...';
    _backupProgress = null;
    _transferStep = null;
    _transferMessage = null;
    _transferProgress = null;
    _isTransferringFile = false;
    notifyListeners();
  }

  void _onBackupProgress(String step, String message, double progress) {
    _backupStep = step;
    _backupMessage = message;
    _backupProgress = progress;
    notifyListeners();
  }

  void _onQueueEvent(QueueEvent event) {
    if (_activeRunId == null || event.runId != _activeRunId) {
      return;
    }
    if (event.isQueued) {
      _backupStep = 'Na fila';
      _backupMessage =
          event.message ??
          (event.queuePosition != null
              ? 'Posição ${event.queuePosition} na fila do servidor'
              : 'Aguardando slot no servidor');
      _backupProgress ??= 0;
      notifyListeners();
      return;
    }
    if (event.isStarted) {
      _backupStep = 'Em execução';
      _backupMessage = event.message ?? 'Backup iniciado no servidor';
      notifyListeners();
    }
  }

  static const String _artifactExpiredMessage =
      'Artefato expirou no servidor; execute um novo backup.';

  bool _isArtifactUsableForResume(ArtifactMetadataResult artifact) {
    if (!artifact.found || artifact.stagingPath == null) {
      return false;
    }
    if (_connectionManager.isArtifactRetentionSupported && artifact.isExpired) {
      return false;
    }
    return true;
  }

  Future<bool> _runServerPreflightGate() async {
    final result = await _connectionManager.validateServerBackupPrerequisites();
    return result.fold(
      (preflight) {
        if (preflight.isBlocked) {
          final detail = preflight.blockingFailures
              .map((c) => c.message)
              .join('\n');
          _resetExecutionState(
            error: detail.isEmpty
                ? 'Servidor bloqueou o backup (preflight)'
                : detail,
          );
          return false;
        }
        if (preflight.hasWarnings) {
          _resetExecutionState();
          return false;
        }
        return true;
      },
      (exception) {
        LoggerService.warning('Preflight remoto falhou: $exception');
        return true;
      },
    );
  }

  Future<bool> _finishBackupAndDownload({
    required String scheduleId,
    required String backupPath,
    String? runId,
  }) async {
    LoggerService.info('===== BACKUP CONCLUÍDO NO SERVIDOR =====');
    LoggerService.info('BackupPath recebido: "$backupPath"');

    if (backupPath.isEmpty) {
      _resetExecutionState();
      return true;
    }

    final transfer = _transferProvider;
    if (transfer == null) {
      _resetExecutionState();
      return true;
    }

    _backupStep = 'Validando pasta local';
    _backupMessage = 'Verificando permissões para download...';
    notifyListeners();

    final hasPermission = await _tempDirectoryService
        .validateDownloadsDirectory();
    if (!hasPermission) {
      final downloadsDir = await _tempDirectoryService.getDownloadsDirectory();
      _resetExecutionState(
        error:
            'Sem permissão de escrita na pasta temporária:\n${downloadsDir.path}\n\n'
            'Configure a pasta em Configurações > Geral ou execute como Administrador.',
      );
      return false;
    }

    _backupStep = 'Baixando arquivo';
    _backupMessage = 'Transferindo backup do servidor...';
    _backupProgress = null;
    notifyListeners();

    final downloadSuccess = await transfer.transferCompletedBackupToClient(
      scheduleId,
      backupPath,
      runId: runId,
      onTransferProgress: (step, message, progress) {
        _backupStep = step;
        _backupMessage = message;
        _backupProgress = progress;
        _transferStep = step;
        _transferMessage = message;
        _transferProgress = progress;
        _isTransferringFile = true;
        notifyListeners();
      },
    );

    if (!downloadSuccess) {
      _resetExecutionState(
        error:
            transfer.error ??
            transfer.uploadError ??
            'Falha ao baixar backup do servidor',
      );
      return false;
    }

    if (transfer.uploadError != null) {
      _resetExecutionState(error: transfer.uploadError);
      return false;
    }

    _resetExecutionState();
    return true;
  }

  /// M8.4: após reconectar, reidrata status e reassina progresso se ainda ativo.
  Future<void> tryResumeExecutionAfterReconnect() async {
    if (!_disconnectedDuringRun ||
        _activeRunId == null ||
        !_connectionManager.isConnected) {
      return;
    }

    // §audit-2026-05-28 wave 2 (P1): guard de re-entrância. Owner único
    // é o `ServerConnectionProvider`, mas se algum callback de UI
    // ainda disparar (page resume, retry manual), o segundo caller
    // simplesmente sai cedo — sem disparar downloads paralelos.
    if (_isResumingAfterReconnect) {
      LoggerService.debug(
        '[remote_schedules] tryResumeExecutionAfterReconnect já em '
        'execução para runId=$_activeRunId; ignorando re-entry',
      );
      return;
    }
    _isResumingAfterReconnect = true;

    try {
      await _tryResumeExecutionAfterReconnectInner();
    } finally {
      _isResumingAfterReconnect = false;
    }
  }

  Future<void> _tryResumeExecutionAfterReconnectInner() async {
    final runId = _activeRunId!;
    final scheduleId = _executingScheduleId;
    if (scheduleId == null) {
      _disconnectedDuringRun = false;
      return;
    }

    _isExecuting = true;
    _error = null;
    _backupStep = 'Reconectado';
    _backupMessage = 'Consultando status do backup no servidor...';
    notifyListeners();

    final statusResult = await _connectionManager.getExecutionStatus(runId);
    await statusResult.fold(
      (status) async {
        if (status.state == ExecutionState.running) {
          _disconnectedDuringRun = false;
          _connectionManager.attachRemoteBackupListener(
            runId: runId,
            onProgress: _onBackupProgress,
          );
          _backupMessage = 'Backup em andamento no servidor';
          notifyListeners();
          final pathResult = await _connectionManager
              .waitForRemoteBackupCompletion(
                runId,
              );
          await pathResult.fold(
            (path) => _finishBackupAndDownload(
              scheduleId: scheduleId,
              backupPath: path,
              runId: runId,
            ),
            (exception) async {
              _resetExecutionState(
                error: mapExceptionToMessage(exception),
                errorCode: exception is Failure ? exception.code : null,
              );
            },
          );
          return;
        }

        if (status.state == ExecutionState.queued) {
          _disconnectedDuringRun = false;
          final polled = await _pollUntilRunningOrTerminal(runId);
          await polled.fold(
            (next) async {
              if (next == ExecutionState.running) {
                _connectionManager.attachRemoteBackupListener(
                  runId: runId,
                  onProgress: _onBackupProgress,
                );
                final pathResult = await _connectionManager
                    .waitForRemoteBackupCompletion(runId);
                await pathResult.fold(
                  (path) => _finishBackupAndDownload(
                    scheduleId: scheduleId,
                    backupPath: path,
                    runId: runId,
                  ),
                  (exception) async {
                    _resetExecutionState(
                      error: mapExceptionToMessage(exception),
                    );
                  },
                );
                return;
              }
              if (next == ExecutionState.completed) {
                final meta = await _connectionManager.getArtifactMetadata(
                  runId: runId,
                );
                await meta.fold(
                  (artifact) async {
                    if (!_isArtifactUsableForResume(artifact)) {
                      _resetExecutionState(
                        error:
                            artifact.isExpired &&
                                _connectionManager.isArtifactRetentionSupported
                            ? _artifactExpiredMessage
                            : 'Backup concluído sem artefato no servidor',
                      );
                      return;
                    }
                    await _finishBackupAndDownload(
                      scheduleId: scheduleId,
                      backupPath: artifact.stagingPath!,
                      runId: runId,
                    );
                  },
                  (exception) async {
                    _resetExecutionState(
                      error: mapExceptionToMessage(exception),
                    );
                  },
                );
                return;
              }
              _resetExecutionState(
                error: next == ExecutionState.cancelled
                    ? 'Backup cancelado no servidor'
                    : 'Backup falhou no servidor',
              );
            },
            (exception) async {
              _resetExecutionState(error: mapExceptionToMessage(exception));
            },
          );
          return;
        }

        if (status.state == ExecutionState.notFound) {
          final meta = await _connectionManager.getArtifactMetadata(
            runId: runId,
          );
          await meta.fold(
            (artifact) async {
              if (_isArtifactUsableForResume(artifact)) {
                await _finishBackupAndDownload(
                  scheduleId: scheduleId,
                  backupPath: artifact.stagingPath!,
                  runId: runId,
                );
                return;
              }
              if (artifact.isExpired &&
                  _connectionManager.isArtifactRetentionSupported) {
                _resetExecutionState(error: _artifactExpiredMessage);
                return;
              }
              _resetExecutionState(
                error:
                    'Execução não encontrada no servidor após reconexão. '
                    'Dispare o backup novamente.',
              );
            },
            (exception) async {
              _resetExecutionState(error: mapExceptionToMessage(exception));
            },
          );
          return;
        }

        if (status.state == ExecutionState.completed) {
          _disconnectedDuringRun = false;
          final meta = await _connectionManager.getArtifactMetadata(
            runId: runId,
          );
          await meta.fold(
            (artifact) async {
              if (!_isArtifactUsableForResume(artifact)) {
                _resetExecutionState(
                  error:
                      artifact.isExpired &&
                          _connectionManager.isArtifactRetentionSupported
                      ? _artifactExpiredMessage
                      : 'Backup concluído, mas artefato não encontrado no servidor',
                );
                return;
              }
              await _finishBackupAndDownload(
                scheduleId: scheduleId,
                backupPath: artifact.stagingPath!,
                runId: runId,
              );
            },
            (exception) async {
              _resetExecutionState(error: mapExceptionToMessage(exception));
            },
          );
          return;
        }

        if (status.state == ExecutionState.failed ||
            status.state == ExecutionState.cancelled) {
          _resetExecutionState(
            error:
                status.message ??
                (status.state == ExecutionState.cancelled
                    ? 'Backup cancelado no servidor'
                    : 'Backup falhou no servidor'),
          );
          return;
        }

        _resetExecutionState(
          error:
              'Execução não encontrada no servidor após reconexão. '
              'Dispare o backup novamente.',
        );
      },
      (exception) async {
        _resetExecutionState(error: mapExceptionToMessage(exception));
      },
    );
  }

  Future<rd.Result<ExecutionState>> _pollUntilRunningOrTerminal(
    String runId,
  ) async {
    final deadline = DateTime.now().add(SocketConfig.backupExecutionTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!_connectionManager.isConnected) {
        return rd.Failure(Exception('Desconectado'));
      }
      final statusResult = await _connectionManager.getExecutionStatus(runId);
      final status = statusResult.getOrNull();
      if (status == null) {
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      if (status.state == ExecutionState.running || status.state.isTerminal) {
        return rd.Success(status.state);
      }
      if (status.state == ExecutionState.queued) {
        _backupMessage = status.queuedPosition != null
            ? 'Na fila do servidor (posição ${status.queuedPosition})'
            : 'Na fila do servidor';
        notifyListeners();
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return rd.Failure(
      TimeoutException('Tempo esgotado aguardando fila remota'),
    );
  }

  void _resetExecutionState({String? error, String? errorCode}) {
    _isExecuting = false;
    _executingScheduleId = null;
    _activeRunId = null;
    _disconnectedDuringRun = false;
    _backupStep = null;
    _backupMessage = null;
    _backupProgress = null;
    _transferStep = null;
    _transferMessage = null;
    _transferProgress = null;
    _isTransferringFile = false;
    _error = error;
    _lastErrorCode = errorCode;
    // §audit-2026-05-28 wave 3 (P2): limpar o snapshot persistido.
    // Reset é sempre terminal — sucesso, falha ou cancelamento — não
    // queremos que o próximo boot tente "resumir" algo já encerrado.
    unawaited(_clearPendingRemoteRunSnapshot());
    notifyListeners();
  }

  // ---------------------------------------------------------------
  // Snapshot persistido de execução remota (P2 wave 3)
  // ---------------------------------------------------------------

  /// Grava `{runId, scheduleId, startedAt}` em
  /// `IMachineSettingsRepository`. Best-effort: falha de I/O só vira
  /// warning para não atrapalhar o fluxo de execução em si.
  Future<void> _persistPendingRemoteRunSnapshot({
    required String runId,
    required String scheduleId,
  }) async {
    final settings = _machineSettings;
    if (settings == null) return;
    try {
      final json = jsonEncode({
        'v': 1,
        'runId': runId,
        'scheduleId': scheduleId,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await settings.setPendingRemoteRunSnapshotJson(json);
    } on Object catch (e, s) {
      LoggerService.warning(
        '[remote_schedules] Falha ao persistir snapshot de run pendente: $e',
        e,
        s,
      );
    }
  }

  Future<void> _clearPendingRemoteRunSnapshot() async {
    final settings = _machineSettings;
    if (settings == null) return;
    try {
      await settings.setPendingRemoteRunSnapshotJson(null);
    } on Object catch (e, s) {
      LoggerService.warning(
        '[remote_schedules] Falha ao limpar snapshot de run pendente: $e',
        e,
        s,
      );
    }
  }

  /// Lê o snapshot persistido (se existir) e popula `_activeRunId` /
  /// `_executingScheduleId` em modo "desconectado durante run". A
  /// próxima `ConnectionStatus.connected` dispara o
  /// `tryResumeExecutionAfterReconnect` que já existia, agora cobrindo
  /// o caminho de **restart do processo** além de simples drop de
  /// conexão.
  Future<void> _restorePendingRemoteRunFromDisk() async {
    final settings = _machineSettings;
    if (settings == null) return;
    try {
      final raw = await settings.getPendingRemoteRunSnapshotJson();
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final runId = decoded['runId'] as String?;
      final scheduleId = decoded['scheduleId'] as String?;
      if (runId == null || runId.isEmpty) return;
      if (scheduleId == null || scheduleId.isEmpty) return;
      _activeRunId = runId;
      _executingScheduleId = scheduleId;
      _disconnectedDuringRun = true;
      _backupStep = 'Aguardando reconexão';
      _backupMessage =
          'Execução remota pendente detectada do boot anterior; '
          'retomaremos assim que a conexão for restabelecida.';
      LoggerService.info(
        '[remote_schedules] Snapshot pré-restart restaurado: '
        'runId=$runId, scheduleId=$scheduleId',
      );
      notifyListeners();
    } on Object catch (e, s) {
      LoggerService.warning(
        '[remote_schedules] Falha ao restaurar snapshot pré-restart: $e',
        e,
        s,
      );
    }
  }

  Future<bool> cancelQueuedRemoteBackup(String runId) async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para cancelar itens da fila.';
      _lastErrorCode = null;
      notifyListeners();
      return false;
    }
    if (!_connectionManager.isExecutionQueueSupported) {
      _error = 'Servidor não suporta cancelamento na fila remota.';
      _lastErrorCode = null;
      notifyListeners();
      return false;
    }
    if (runId.isEmpty) {
      _error = 'Identificador de execução inválido.';
      _lastErrorCode = null;
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
        _error =
            cancelResult.message ?? 'Item não encontrado na fila do servidor.';
        _lastErrorCode = null;
        notifyListeners();
        return false;
      },
      (exception) {
        _error = mapExceptionToMessage(exception);
        _lastErrorCode = exception is Failure ? exception.code : null;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> cancelSchedule() async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para cancelar agendamentos.';
      _lastErrorCode = null;
      notifyListeners();
      return false;
    }

    if (_executingScheduleId == null) {
      _error = 'Nenhum backup em execução para cancelar.';
      _lastErrorCode = null;
      notifyListeners();
      return false;
    }

    final result = _activeRunId != null && _connectionManager.isRunIdSupported
        ? await _connectionManager.cancelRemoteBackup(runId: _activeRunId)
        : await _connectionManager.cancelSchedule(_executingScheduleId!);

    return result.fold(
      (_) {
        _resetExecutionState();
        return true;
      },
      (exception) {
        _error = mapExceptionToMessage(exception);
        _lastErrorCode = exception is Failure ? exception.code : null;
        notifyListeners();
        return false;
      },
    );
  }

  void clearError() {
    _error = null;
    _lastErrorCode = null;
    notifyListeners();
  }

  static const String _connectionLostMessage =
      'Conexão perdida; consultando servidor após reconectar...';

  void clearExecutionStateOnDisconnect() {
    if (_executingScheduleId == null) return;
    _disconnectedDuringRun = _activeRunId != null;
    _isExecuting = false;
    _backupStep = null;
    _backupMessage = null;
    _backupProgress = null;
    _transferStep = null;
    _transferMessage = null;
    _transferProgress = null;
    _isTransferringFile = false;
    _error = _disconnectedDuringRun
        ? _connectionLostMessage
        : 'Conexão perdida durante o backup.';
    _lastErrorCode = null;
    notifyListeners();
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
