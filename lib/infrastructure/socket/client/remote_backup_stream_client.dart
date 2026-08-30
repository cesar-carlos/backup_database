import 'dart:async';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/queue_events.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/client/backup_event_deduplicator.dart';
import 'package:backup_database/infrastructure/socket/client/client_rpc_transport.dart';
import 'package:backup_database/infrastructure/socket/client/remote_backup_types.dart';
import 'package:backup_database/infrastructure/socket/client/remote_diagnostics_rpc.dart';
import 'package:backup_database/infrastructure/socket/client/remote_session_rpc.dart';
import 'package:result_dart/result_dart.dart' as rd;

class BackupProgressState {
  BackupProgressState({
    required this.completer,
    this.onProgress,
    this.runId,
  });

  final Completer<rd.Result<String>> completer;
  final BackupProgressCallback? onProgress;
  String? runId;
}

class RemoteBackupStreamClient {
  RemoteBackupStreamClient({
    required this._rpc,
    required this._isConnected,
    required this._send,
    required this._sessionRpc,
    required this._diagnosticsRpc,
  });

  final ClientRpcTransport _rpc;
  final bool Function() _isConnected;
  final Future<void> Function(Message message) _send;
  final RemoteSessionRpc _sessionRpc;
  final RemoteDiagnosticsRpc _diagnosticsRpc;

  static const Duration _executionStatusPollInterval = Duration(seconds: 2);
  static const int _maxPendingBackupStreamEventsPerRunId = 64;

  final Map<int, BackupProgressState> _activeBackups = {};
  final Map<String, BackupProgressState> _activeBackupsByRunId = {};
  final Map<String, double> _lastProgressByRunId = <String, double>{};
  final Map<String, List<Message>> _pendingBackupStreamByRunId = {};
  final BackupEventDeduplicator _backupEventDedup = BackupEventDeduplicator();

  bool get hasActiveBackups =>
      _activeBackups.isNotEmpty || _activeBackupsByRunId.isNotEmpty;
  int get activeCount => _activeBackups.length;

  BackupProgressState? backupForRequestId(int requestId) =>
      _activeBackups[requestId];

  BackupProgressState? backupForRunId(String runId) =>
      _activeBackupsByRunId[runId];

  bool shouldAcceptQueueEvent({
    required String? eventId,
    required int? sequence,
    required String runId,
  }) {
    return _backupEventDedup.shouldAcceptFields(
      eventId: eventId,
      sequence: sequence,
      runId: runId,
    );
  }

  void abortAll(Object failure) {
    final exception = failure is Exception ? failure : Exception('$failure');
    for (final state in _activeBackups.values) {
      if (!state.completer.isCompleted) {
        state.completer.complete(rd.Failure(exception));
      }
    }
    _activeBackups.clear();
    for (final state in _activeBackupsByRunId.values) {
      if (!state.completer.isCompleted) {
        state.completer.complete(rd.Failure(exception));
      }
    }
    _activeBackupsByRunId.clear();
    _lastProgressByRunId.clear();
    _pendingBackupStreamByRunId.clear();
    _backupEventDedup.clear();
  }

  void handleQueueEvent(QueueEvent event) {
    final state = _activeBackupsByRunId[event.runId];
    final onProgress = state?.onProgress;
    if (onProgress == null) {
      return;
    }
    if (event.isQueued) {
      final positionText = event.queuePosition != null
          ? 'Posição ${event.queuePosition} na fila do servidor'
          : 'Aguardando slot no servidor';
      onProgress(
        'Na fila',
        event.message ?? positionText,
        _lastProgressByRunId[event.runId] ?? 0,
      );
      return;
    }
    if (event.isDequeued) {
      if (event.reason == 'cancelled') {
        onProgress(
          'Cancelado',
          event.message ?? 'Backup removido da fila do servidor',
          _lastProgressByRunId[event.runId] ?? 0,
        );
      }
      return;
    }
    if (event.isStarted) {
      onProgress(
        'Em execução',
        event.message ?? 'Backup iniciado no servidor',
        _lastProgressByRunId[event.runId] ?? 0,
      );
    }
  }

  void bufferUntilListener({required String runId, required Message message}) {
    final pending = _pendingBackupStreamByRunId.putIfAbsent(
      runId,
      () => <Message>[],
    );
    if (pending.length >= _maxPendingBackupStreamEventsPerRunId) {
      pending.removeAt(0);
    }
    pending.add(message);
  }

  void handleBackupProgressMessage(Message message, BackupProgressState state) {
    if (!_backupEventDedup.shouldAccept(message)) {
      LoggerService.debug(
        '[ConnectionManager] evento de backup duplicado ignorado '
        '(eventId/sequence): ${message.header.type.name}',
      );
      return;
    }

    LoggerService.info(
      '[ConnectionManager._handleBackupProgressMessage] Tipo: ${message.header.type.name}, RequestID: ${message.header.requestId}',
    );
    LoggerService.info(
      '[ConnectionManager._handleBackupProgressMessage] Payload: ${message.payload}',
    );

    final messageRunId = getRunIdFromBackupMessage(message);
    if (messageRunId != null && state.runId == null) {
      state.runId = messageRunId;
      LoggerService.debug(
        '[ConnectionManager] runId capturado para backup: $messageRunId',
      );
    }

    if (isBackupStepMessage(message)) {
      final step = getStepFromBackupStep(message) ?? '';
      final progressMessage = getMessageFromBackupStep(message) ?? '';
      final progress = getProgressFromBackupStep(message);
      state.onProgress?.call(
        step,
        progressMessage,
        progress ?? _lastProgressByRunId[state.runId] ?? 0.0,
      );
      return;
    }
    if (isBackupProgressMessage(message)) {
      final step = getStepFromBackupProgress(message) ?? '';
      final progressMessage = getMessageFromBackupProgress(message) ?? '';
      final progress = getProgressFromBackupProgress(message) ?? 0.0;
      if (state.runId != null && state.runId!.isNotEmpty) {
        _lastProgressByRunId[state.runId!] = progress;
      }
      state.onProgress?.call(step, progressMessage, progress);
      return;
    }
    if (isBackupCompleteMessage(message)) {
      LoggerService.info(
        '[ConnectionManager] ✓ Mensagem backupComplete recebida!'
        '${state.runId != null ? ' (runId=${state.runId})' : ''}',
      );
      final path = getBackupPathFromBackupComplete(message);
      LoggerService.info('[ConnectionManager] backupPath extraído: "$path"');
      _removeBackupProgressState(message, state);
      state.onProgress?.call('Concluído', 'Backup concluído com sucesso!', 1);
      if (!state.completer.isCompleted) {
        state.completer.complete(rd.Success(path ?? ''));
      }
      return;
    }
    if (isBackupFailedMessage(message)) {
      _removeBackupProgressState(message, state);
      final error = getErrorFromBackupFailed(message) ?? 'Erro desconhecido';
      LoggerService.warning(
        '[ConnectionManager] backupFailed'
        '${state.runId != null ? ' (runId=${state.runId})' : ''}: $error',
      );
      state.completer.complete(rd.Failure(Exception(error)));
      return;
    }
    if (message.header.type == MessageType.backupCancelled) {
      _removeBackupProgressState(message, state);
      final cancelledBy =
          getCancelledByFromBackupCancelled(message) ?? 'desconhecido';
      final reason = getReasonFromBackupCancelled(message);
      final occurredAt = getOccurredAtFromBackupCancelled(message);
      LoggerService.info(
        '[ConnectionManager] backupCancelled'
        '${state.runId != null ? ' (runId=${state.runId})' : ''} '
        'por=$cancelledBy reason=${reason ?? '-'}',
      );
      state.onProgress?.call(
        'Cancelado',
        reason ?? 'Backup cancelado por $cancelledBy',
        _lastProgressByRunId[state.runId] ?? 0,
      );
      state.completer.complete(
        rd.Failure(
          RemoteBackupCancelledException(
            cancelledBy: cancelledBy,
            reason: reason,
            occurredAt: occurredAt,
          ),
        ),
      );
    }
  }

  void _removeBackupProgressState(Message message, BackupProgressState state) {
    _activeBackups.remove(message.header.requestId);
    final runId = state.runId ?? getRunIdFromBackupMessage(message);
    if (runId != null && runId.isNotEmpty) {
      _backupEventDedup.forgetRun(runId);
      _lastProgressByRunId.remove(runId);
    }
  }

  void _replayPendingBackupStream(String runId, BackupProgressState state) {
    final pending = _pendingBackupStreamByRunId.remove(runId);
    if (pending == null) {
      return;
    }
    for (final message in pending) {
      handleBackupProgressMessage(message, state);
    }
  }

  void ensureListener({
    required String runId,
    required BackupProgressCallback? onProgress,
  }) {
    final existing = _activeBackupsByRunId[runId];
    if (existing != null && !existing.completer.isCompleted) {
      _activeBackupsByRunId[runId] = BackupProgressState(
        completer: existing.completer,
        onProgress: onProgress,
        runId: runId,
      );
      return;
    }
    final state = BackupProgressState(
      completer: Completer<rd.Result<String>>(),
      onProgress: onProgress,
      runId: runId,
    );
    _activeBackupsByRunId[runId] = state;
    _replayPendingBackupStream(runId, state);
  }

  void attachListener({
    required String runId,
    required BackupProgressCallback? onProgress,
  }) {
    ensureListener(runId: runId, onProgress: onProgress);
  }

  Future<rd.Result<String>> waitForCompletion(String runId) {
    return _awaitRegistered(runId);
  }

  @Deprecated(
    'Use executeRemoteBackup para aceite imediato + acompanhamento por runId. '
    'Sera removido em PR futuro apos 2 releases com este aviso.',
  )
  Future<rd.Result<String>> executeSchedule(
    String scheduleId, {
    BackupProgressCallback? onProgress,
  }) async {
    if (!_isConnected()) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _rpc.allocateRequestId();
    final completer = Completer<rd.Result<String>>();

    if (onProgress != null) {
      _activeBackups[requestId] = BackupProgressState(
        completer: completer,
        onProgress: onProgress,
      );
    }

    try {
      await _send(
        createExecuteScheduleMessage(
          requestId: requestId,
          scheduleId: scheduleId,
        ),
      );

      final result = await completer.future.timeout(
        SocketConfig.backupExecutionTimeout,
      );
      _activeBackups.remove(requestId);
      return result;
    } on TimeoutException {
      _activeBackups.remove(requestId);
      return rd.Failure(
        TimeoutException(
          'Tempo esgotado ao aguardar conclusão do backup '
          '(limite: ${SocketConfig.backupExecutionTimeout.inMinutes} minutos)',
        ),
      );
    } on Object catch (e) {
      _activeBackups.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<rd.Result<String>> executeRemoteBackup({
    required String scheduleId,
    String? idempotencyKey,
    bool queueIfBusy = true,
    BackupProgressCallback? onProgress,
    void Function(String runId)? onRunIdKnown,
  }) async {
    if (!_isConnected()) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }

    final startResult = await _sessionRpc.startRemoteBackup(
      scheduleId: scheduleId,
      idempotencyKey: idempotencyKey,
      queueIfBusy: queueIfBusy,
    );

    return startResult.fold(
      (start) async {
        final runId = start.runId;
        if (runId.isEmpty) {
          return rd.Failure(Exception('Servidor não retornou runId'));
        }
        onRunIdKnown?.call(runId);

        if (start.state == ExecutionState.queued ||
            start.state == ExecutionState.running) {
          ensureListener(runId: runId, onProgress: onProgress);
        }

        if (start.state == ExecutionState.queued) {
          final waitResult = await _waitForQueuedRemoteBackup(
            runId: runId,
            onProgress: onProgress,
          );
          return waitResult.fold(
            (terminal) async {
              if (terminal == ExecutionState.running ||
                  terminal == ExecutionState.completed) {
                return _awaitRegistered(runId);
              }
              if (terminal == ExecutionState.failed) {
                return _awaitRegistered(runId);
              }
              return _resolveBackupPathForTerminal(runId, terminal);
            },
            rd.Failure.new,
          );
        }

        if (start.state == ExecutionState.running) {
          return _awaitRegistered(runId);
        }

        if (start.state.isTerminal) {
          return _resolveBackupPathForTerminal(runId, start.state);
        }

        return rd.Failure(
          Exception(
            start.message ?? 'Servidor recusou iniciar backup remoto',
          ),
        );
      },
      rd.Failure.new,
    );
  }

  Future<rd.Result<String>> _awaitRegistered(String runId) async {
    final state = _activeBackupsByRunId[runId];
    if (state == null) {
      return rd.Failure(
        Exception('Nenhum acompanhamento ativo para runId: $runId'),
      );
    }
    try {
      return await state.completer.future.timeout(
        SocketConfig.backupExecutionTimeout,
      );
    } on TimeoutException {
      return rd.Failure(
        TimeoutException(
          'Tempo esgotado ao aguardar conclusão do backup remoto',
        ),
      );
    } finally {
      _activeBackupsByRunId.remove(runId);
    }
  }

  Future<rd.Result<ExecutionState>?> _queuedPollShortcutIfBackupSettled(
    String runId,
  ) async {
    final active = _activeBackupsByRunId[runId];
    if (active == null || !active.completer.isCompleted) {
      return null;
    }
    return const rd.Success(ExecutionState.completed);
  }

  Future<rd.Result<ExecutionState>> _waitForQueuedRemoteBackup({
    required String runId,
    BackupProgressCallback? onProgress,
  }) async {
    final deadline = DateTime.now().add(SocketConfig.backupExecutionTimeout);

    while (DateTime.now().isBefore(deadline)) {
      if (!_isConnected()) {
        return rd.Failure(Exception('Desconectado enquanto aguardava fila'));
      }

      final settled = await _queuedPollShortcutIfBackupSettled(runId);
      if (settled != null) {
        return settled;
      }

      final statusResult = await _sessionRpc.getExecutionStatus(runId);
      final status = statusResult.getOrNull();
      if (status == null) {
        await Future<void>.delayed(_executionStatusPollInterval);
        continue;
      }

      if (status.state == ExecutionState.running) {
        return const rd.Success(ExecutionState.running);
      }
      if (status.state == ExecutionState.queued) {
        onProgress?.call(
          'Na fila',
          status.queuedPosition != null
              ? 'Posição ${status.queuedPosition} na fila do servidor'
              : 'Aguardando slot no servidor',
          0,
        );
        await Future<void>.delayed(_executionStatusPollInterval);
        continue;
      }
      if (status.state.isTerminal) {
        return rd.Success(status.state);
      }
      if (status.state == ExecutionState.notFound) {
        final afterNotFound = await _queuedPollShortcutIfBackupSettled(runId);
        if (afterNotFound != null) {
          return afterNotFound;
        }
        return rd.Failure(
          Exception(
            'Execução não encontrada no servidor (runId pode ter expirado)',
          ),
        );
      }
      await Future<void>.delayed(_executionStatusPollInterval);
    }

    return rd.Failure(
      TimeoutException('Tempo esgotado aguardando saída da fila remota'),
    );
  }

  Future<rd.Result<String>> _resolveBackupPathForTerminal(
    String runId,
    ExecutionState state,
  ) async {
    switch (state) {
      case ExecutionState.completed:
        final metaResult = await _diagnosticsRpc.getArtifactMetadata(
          runId: runId,
        );
        return metaResult.fold(
          (meta) {
            if (!meta.found || meta.stagingPath == null) {
              return rd.Failure(
                Exception('Artefato não encontrado no staging do servidor'),
              );
            }
            if (meta.isExpired) {
              return rd.Failure(
                Exception('Artefato expirou no servidor; execute novo backup'),
              );
            }
            return rd.Success(meta.stagingPath!);
          },
          rd.Failure.new,
        );
      case ExecutionState.failed:
        final statusResult = await _sessionRpc.getExecutionStatus(runId);
        final message = statusResult.fold((s) => s.message, (_) => null);
        return rd.Failure(
          Exception(message ?? 'Backup remoto falhou no servidor'),
        );
      case ExecutionState.cancelled:
        return rd.Failure(Exception('Backup remoto foi cancelado'));
      case ExecutionState.running:
      case ExecutionState.queued:
      case ExecutionState.notFound:
      case ExecutionState.unknown:
        return rd.Failure(
          Exception('Estado inesperado ao resolver artefato: ${state.name}'),
        );
    }
  }
}

bool isBackupStreamMessage(MessageType type) =>
    type == MessageType.backupProgress ||
    type == MessageType.backupStep ||
    type == MessageType.backupComplete ||
    type == MessageType.backupFailed ||
    type == MessageType.backupCancelled;
