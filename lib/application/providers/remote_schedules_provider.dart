import 'dart:async';

import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/utils/error_mapper.dart'
    show mapExceptionToMessage;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:uuid/uuid.dart';

class RemoteSchedulesProvider extends ChangeNotifier {
  RemoteSchedulesProvider(
    this._connectionManager, {
    RemoteFileTransferProvider? transferProvider,
    TempDirectoryService? tempDirectoryService,
  }) : _transferProvider = transferProvider,
       _tempDirectoryService =
           tempDirectoryService ?? getIt<TempDirectoryService>();

  final ConnectionManager _connectionManager;
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

  String? _backupStep;
  String? _backupMessage;
  double? _backupProgress;

  String? _transferStep;
  String? _transferMessage;
  double? _transferProgress;
  bool _isTransferringFile = false;

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

  Future<bool> executeSchedule(String scheduleId) async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para executar agendamentos.';
      _lastErrorCode = null;
      notifyListeners();
      return false;
    }

    _beginExecution(scheduleId);

    if (_connectionManager.isRunIdSupported) {
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
              notifyListeners();
            },
          )
        : await _connectionManager.executeSchedule(
            scheduleId,
            onProgress: _onBackupProgress,
          );

    return backupResult.fold(
      (backupPath) => _finishBackupAndDownload(
        scheduleId: scheduleId,
        backupPath: backupPath,
        runId: _activeRunId,
      ),
      (exception) {
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
    final raw = failure.toString();
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
          _backupStep = 'Avisos do servidor';
          _backupMessage = preflight.warnings.map((c) => c.message).join('; ');
          notifyListeners();
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

    final hasPermission = await _tempDirectoryService.validateDownloadsDirectory();
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

    _resetExecutionState();
    return downloadSuccess;
  }

  /// M8.4: após reconectar, reidrata status e reassina progresso se ainda ativo.
  Future<void> tryResumeExecutionAfterReconnect() async {
    if (!_disconnectedDuringRun ||
        _activeRunId == null ||
        !_connectionManager.isConnected) {
      return;
    }

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
          final pathResult = await _connectionManager.waitForRemoteBackupCompletion(
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
                final pathResult =
                    await _connectionManager.waitForRemoteBackupCompletion(runId);
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
                    if (!artifact.found || artifact.stagingPath == null) {
                      _resetExecutionState(
                        error: 'Backup concluído sem artefato no servidor',
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
          final meta = await _connectionManager.getArtifactMetadata(runId: runId);
          await meta.fold(
            (artifact) async {
              if (artifact.found && artifact.stagingPath != null) {
                await _finishBackupAndDownload(
                  scheduleId: scheduleId,
                  backupPath: artifact.stagingPath!,
                  runId: runId,
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
          return;
        }

        if (status.state == ExecutionState.completed) {
          _disconnectedDuringRun = false;
          final meta = await _connectionManager.getArtifactMetadata(runId: runId);
          await meta.fold(
            (artifact) async {
              if (!artifact.found || artifact.stagingPath == null) {
                _resetExecutionState(
                  error: 'Backup concluído, mas artefato não encontrado no servidor',
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
            error: status.message ??
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
      if (status.state == ExecutionState.running ||
          status.state.isTerminal) {
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
    return rd.Failure(TimeoutException('Tempo esgotado aguardando fila remota'));
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
    notifyListeners();
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
}
