import 'dart:async';

import 'package:backup_database/application/providers/remote/pending_remote_run_store.dart';
import 'package:backup_database/application/providers/remote/remote_schedules_run_session.dart';
import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/core/errors/failure.dart'
    show Failure, failureUserMessage;
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/utils/error_mapper.dart'
    show mapExceptionToMessage;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:uuid/uuid.dart';

typedef EnsureServerHealthyForBackup = Future<bool> Function();

class RemoteScheduleExecutionCoordinator {
  RemoteScheduleExecutionCoordinator({
    required ConnectionManager connectionManager,
    required RemoteSchedulesRunSession session,
    required PendingRemoteRunStore pendingRunStore,
    required TempDirectoryService tempDirectoryService,
    required EnsureServerHealthyForBackup ensureServerHealthy,
    required Future<void> Function() loadExecutionQueue,
    RemoteFileTransferProvider? transferProvider,
  }) : _connectionManager = connectionManager,
       _session = session,
       _pendingRunStore = pendingRunStore,
       _tempDirectoryService = tempDirectoryService,
       _ensureServerHealthy = ensureServerHealthy,
       _loadExecutionQueue = loadExecutionQueue,
       _transferProvider = transferProvider;

  final ConnectionManager _connectionManager;
  final RemoteSchedulesRunSession _session;
  final PendingRemoteRunStore _pendingRunStore;
  final TempDirectoryService _tempDirectoryService;
  final EnsureServerHealthyForBackup _ensureServerHealthy;
  final Future<void> Function() _loadExecutionQueue;
  final RemoteFileTransferProvider? _transferProvider;

  Future<bool> executeSchedule(
    String scheduleId, {
    bool skipPreflightCheck = false,
  }) async {
    if (!_connectionManager.isConnected) {
      _session.error = 'Conecte-se a um servidor para executar agendamentos.';
      _session.lastErrorCode = null;
      _session.notifyListeners();
      return false;
    }

    if (_connectionManager.isRunIdSupported) {
      final isHealthy = await _ensureServerHealthy();
      if (!isHealthy) {
        _session.error =
            'Servidor indisponível ou com problemas de saúde. '
            'Atualize o status da conexão e tente novamente.';
        _session.lastErrorCode = null;
        _session.notifyListeners();
        return false;
      }
    }

    _session.beginExecution(scheduleId);

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
            onProgress: _session.onBackupProgress,
            onRunIdKnown: (runId) {
              _session.activeRunId = runId;
              unawaited(
                _pendingRunStore.persist(
                  runId: runId,
                  scheduleId: scheduleId,
                ),
              );
              _session.notifyListeners();
            },
          )
        // Fallback consciente para servidor `v1` sem `supportsRunId`.
        // ignore: deprecated_member_use_from_same_package
        : await _connectionManager.executeSchedule(
            scheduleId,
            onProgress: _session.onBackupProgress,
          );

    final finished = await backupResult.fold(
      (backupPath) async => finishBackupAndDownload(
        scheduleId: scheduleId,
        backupPath: backupPath,
        runId: _session.activeRunId,
      ),
      (exception) async {
        if (_shouldPreserveStateAfterDisconnectFailure(exception)) {
          _session.isExecuting = false;
          _session.disconnectedDuringRun = true;
          _session.error = RemoteSchedulesRunSession.connectionLostMessage;
          _session.lastErrorCode = null;
          _session.notifyListeners();
          return false;
        }
        _session.resetExecutionState(
          error: mapExceptionToMessage(exception),
          errorCode: exception is Failure ? exception.code : null,
        );
        return false;
      },
    );
    if (_connectionManager.isExecutionQueueSupported) {
      unawaited(_loadExecutionQueue());
    }
    return finished;
  }

  bool _shouldPreserveStateAfterDisconnectFailure(Object failure) {
    if (_session.activeRunId == null) return false;
    if (_session.disconnectedDuringRun) return true;
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

  Future<bool> _runServerPreflightGate() async {
    final result = await _connectionManager.validateServerBackupPrerequisites();
    return result.fold(
      (preflight) {
        if (preflight.isBlocked) {
          final detail = preflight.blockingFailures
              .map((c) => c.message)
              .join('\n');
          _session.resetExecutionState(
            error: detail.isEmpty
                ? 'Servidor bloqueou o backup (preflight)'
                : detail,
          );
          return false;
        }
        if (preflight.hasWarnings) {
          _session.resetExecutionState();
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

  Future<bool> finishBackupAndDownload({
    required String scheduleId,
    required String backupPath,
    String? runId,
  }) async {
    LoggerService.info('===== BACKUP CONCLUÍDO NO SERVIDOR =====');
    LoggerService.info('BackupPath recebido: "$backupPath"');

    if (backupPath.isEmpty) {
      _session.resetExecutionState();
      return true;
    }

    final transfer = _transferProvider;
    if (transfer == null) {
      _session.resetExecutionState();
      return true;
    }

    _session.backupStep = 'Validando pasta local';
    _session.backupMessage = 'Verificando permissões para download...';
    _session.notifyListeners();

    final hasPermission = await _tempDirectoryService
        .validateDownloadsDirectory();
    if (!hasPermission) {
      final downloadsDir = await _tempDirectoryService.getDownloadsDirectory();
      _session.resetExecutionState(
        error:
            'Sem permissão de escrita na pasta temporária:\n${downloadsDir.path}\n\n'
            'Configure a pasta em Configurações > Geral ou execute como Administrador.',
      );
      return false;
    }

    _session.backupStep = 'Baixando arquivo';
    _session.backupMessage = 'Transferindo backup do servidor...';
    _session.backupProgress = null;
    _session.notifyListeners();

    final downloadSuccess = await transfer.transferCompletedBackupToClient(
      scheduleId,
      backupPath,
      runId: runId,
      onTransferProgress: (step, message, progress) {
        _session.backupStep = step;
        _session.backupMessage = message;
        _session.backupProgress = progress;
        _session.transferStep = step;
        _session.transferMessage = message;
        _session.transferProgress = progress;
        _session.isTransferringFile = true;
        _session.notifyListeners();
      },
    );

    if (!downloadSuccess) {
      _session.resetExecutionState(
        error:
            transfer.error ??
            transfer.uploadError ??
            'Falha ao baixar backup do servidor',
      );
      return false;
    }

    if (transfer.uploadError != null) {
      _session.resetExecutionState(error: transfer.uploadError);
      return false;
    }

    _session.resetExecutionState();
    return true;
  }

  Future<bool> cancelSchedule() async {
    if (!_connectionManager.isConnected) {
      _session.error = 'Conecte-se a um servidor para cancelar agendamentos.';
      _session.lastErrorCode = null;
      _session.notifyListeners();
      return false;
    }

    if (_session.executingScheduleId == null) {
      _session.error = 'Nenhum backup em execução para cancelar.';
      _session.lastErrorCode = null;
      _session.notifyListeners();
      return false;
    }

    final result =
        _session.activeRunId != null && _connectionManager.isRunIdSupported
        ? await _connectionManager.cancelRemoteBackup(
            runId: _session.activeRunId,
          )
        : await _connectionManager.cancelSchedule(
            _session.executingScheduleId!,
          );

    return result.fold(
      (_) {
        _session.resetExecutionState();
        return true;
      },
      (exception) {
        _session.error = mapExceptionToMessage(exception);
        _session.lastErrorCode = exception is Failure ? exception.code : null;
        _session.notifyListeners();
        return false;
      },
    );
  }
}
