import 'dart:async';

import 'package:backup_database/application/providers/remote/remote_schedule_execution_coordinator.dart';
import 'package:backup_database/application/providers/remote/remote_schedules_run_session.dart';
import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/errors/failure.dart' show Failure;
import 'package:backup_database/core/utils/error_mapper.dart'
    show mapExceptionToMessage;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/diagnostics_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:result_dart/result_dart.dart' as rd;

class RemoteRunResumeService {
  RemoteRunResumeService({
    required this._connectionManager,
    required this._session,
    required this._execution,
  });

  final ConnectionManager _connectionManager;
  final RemoteSchedulesRunSession _session;
  final RemoteScheduleExecutionCoordinator _execution;

  Future<void> tryResumeExecutionAfterReconnect() async {
    if (!_session.disconnectedDuringRun ||
        _session.activeRunId == null ||
        !_connectionManager.isConnected) {
      return;
    }

    if (_session.isResumingAfterReconnect) {
      LoggerService.debug(
        '[remote_schedules] tryResumeExecutionAfterReconnect já em '
        'execução para runId=${_session.activeRunId}; ignorando re-entry',
      );
      return;
    }
    _session.isResumingAfterReconnect = true;

    try {
      await _tryResumeExecutionAfterReconnectInner();
    } finally {
      _session.isResumingAfterReconnect = false;
    }
  }

  Future<void> _tryResumeExecutionAfterReconnectInner() async {
    final runId = _session.activeRunId!;
    final scheduleId = _session.executingScheduleId;
    if (scheduleId == null) {
      _session.disconnectedDuringRun = false;
      return;
    }

    _session.isExecuting = true;
    _session.error = null;
    _session.backupStep = 'Reconectado';
    _session.backupMessage = 'Consultando status do backup no servidor...';
    _session.notifyListeners();

    final statusResult = await _connectionManager.getExecutionStatus(runId);
    await statusResult.fold(
      (status) async {
        if (status.state == ExecutionState.running) {
          _session.disconnectedDuringRun = false;
          _connectionManager.attachRemoteBackupListener(
            runId: runId,
            onProgress: _session.onBackupProgress,
          );
          _session.backupMessage = 'Backup em andamento no servidor';
          _session.notifyListeners();
          final pathResult = await _connectionManager
              .waitForRemoteBackupCompletion(
                runId,
              );
          await pathResult.fold(
            (path) => _execution.finishBackupAndDownload(
              scheduleId: scheduleId,
              backupPath: path,
              runId: runId,
            ),
            (exception) async {
              _session.resetExecutionState(
                error: mapExceptionToMessage(exception),
                errorCode: exception is Failure ? exception.code : null,
              );
            },
          );
          return;
        }

        if (status.state == ExecutionState.queued) {
          _session.disconnectedDuringRun = false;
          final polled = await _pollUntilRunningOrTerminal(runId);
          await polled.fold(
            (next) async {
              if (next == ExecutionState.running) {
                _connectionManager.attachRemoteBackupListener(
                  runId: runId,
                  onProgress: _session.onBackupProgress,
                );
                final pathResult = await _connectionManager
                    .waitForRemoteBackupCompletion(runId);
                await pathResult.fold(
                  (path) => _execution.finishBackupAndDownload(
                    scheduleId: scheduleId,
                    backupPath: path,
                    runId: runId,
                  ),
                  (exception) async {
                    _session.resetExecutionState(
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
                      _session.resetExecutionState(
                        error:
                            artifact.isExpired &&
                                _connectionManager.isArtifactRetentionSupported
                            ? RemoteSchedulesRunSession.artifactExpiredMessage
                            : 'Backup concluído sem artefato no servidor',
                      );
                      return;
                    }
                    await _execution.finishBackupAndDownload(
                      scheduleId: scheduleId,
                      backupPath: artifact.stagingPath!,
                      runId: runId,
                    );
                  },
                  (exception) async {
                    _session.resetExecutionState(
                      error: mapExceptionToMessage(exception),
                    );
                  },
                );
                return;
              }
              _session.resetExecutionState(
                error: next == ExecutionState.cancelled
                    ? 'Backup cancelado no servidor'
                    : 'Backup falhou no servidor',
              );
            },
            (exception) async {
              _session.resetExecutionState(
                error: mapExceptionToMessage(exception),
              );
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
                await _execution.finishBackupAndDownload(
                  scheduleId: scheduleId,
                  backupPath: artifact.stagingPath!,
                  runId: runId,
                );
                return;
              }
              if (artifact.isExpired &&
                  _connectionManager.isArtifactRetentionSupported) {
                _session.resetExecutionState(
                  error: RemoteSchedulesRunSession.artifactExpiredMessage,
                );
                return;
              }
              _session.resetExecutionState(
                error:
                    'Execução não encontrada no servidor após reconexão. '
                    'Dispare o backup novamente.',
              );
            },
            (exception) async {
              _session.resetExecutionState(
                error: mapExceptionToMessage(exception),
              );
            },
          );
          return;
        }

        if (status.state == ExecutionState.completed) {
          _session.disconnectedDuringRun = false;
          final meta = await _connectionManager.getArtifactMetadata(
            runId: runId,
          );
          await meta.fold(
            (artifact) async {
              if (!_isArtifactUsableForResume(artifact)) {
                _session.resetExecutionState(
                  error:
                      artifact.isExpired &&
                          _connectionManager.isArtifactRetentionSupported
                      ? RemoteSchedulesRunSession.artifactExpiredMessage
                      : 'Backup concluído, mas artefato não encontrado no servidor',
                );
                return;
              }
              await _execution.finishBackupAndDownload(
                scheduleId: scheduleId,
                backupPath: artifact.stagingPath!,
                runId: runId,
              );
            },
            (exception) async {
              _session.resetExecutionState(
                error: mapExceptionToMessage(exception),
              );
            },
          );
          return;
        }

        if (status.state == ExecutionState.failed ||
            status.state == ExecutionState.cancelled) {
          _session.resetExecutionState(
            error:
                status.message ??
                (status.state == ExecutionState.cancelled
                    ? 'Backup cancelado no servidor'
                    : 'Backup falhou no servidor'),
          );
          return;
        }

        _session.resetExecutionState(
          error:
              'Execução não encontrada no servidor após reconexão. '
              'Dispare o backup novamente.',
        );
      },
      (exception) async {
        _session.resetExecutionState(error: mapExceptionToMessage(exception));
      },
    );
  }

  bool _isArtifactUsableForResume(ArtifactMetadataResult artifact) {
    if (!artifact.found || artifact.stagingPath == null) {
      return false;
    }
    if (_connectionManager.isArtifactRetentionSupported && artifact.isExpired) {
      return false;
    }
    return true;
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
        _session.backupMessage = status.queuedPosition != null
            ? 'Na fila do servidor (posição ${status.queuedPosition})'
            : 'Na fila do servidor';
        _session.notifyListeners();
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return rd.Failure(
      TimeoutException('Tempo esgotado aguardando fila remota'),
    );
  }
}
