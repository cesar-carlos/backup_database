import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_service.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart'
    show RemoteExecutionRegistry, SendToClient;

/// Responde `executionStatusRequest` com o estado atual de uma
/// execucao remota identificada por `runId`.
///
/// Ordem de resolucao (PR-3c):
/// 1. [RemoteExecutionRegistry] — `running` com snapshot.
/// 2. [ExecutionQueueService.findQueuedByRunId] — `queued`.
/// 3. [IBackupHistoryRepository.getByRunId] — estados terminais ou
///    `running` reidratado do SQLite (apos restart, sem registry).
/// 4. [ExecutionState.notFound].
class ExecutionStatusMessageHandler {
  ExecutionStatusMessageHandler({
    required RemoteExecutionRegistry executionRegistry,
    ExecutionQueueService? queueService,
    IBackupHistoryRepository? backupHistoryRepository,
    DateTime Function()? clock,
  }) : _executionRegistry = executionRegistry,
       _queueService = queueService,
       _backupHistoryRepository = backupHistoryRepository,
       _clock = clock ?? DateTime.now;

  final RemoteExecutionRegistry _executionRegistry;
  final ExecutionQueueService? _queueService;
  final IBackupHistoryRepository? _backupHistoryRepository;
  final DateTime Function() _clock;

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    if (!isExecutionStatusRequestMessage(message)) return;

    final requestId = message.header.requestId;
    final runId = getRunIdFromExecutionStatusRequest(message);

    if (runId == null || runId.isEmpty) {
      LoggerService.infoWithContext(
        'ExecutionStatusMessageHandler: runId vazio na requisicao',
        clientId: clientId,
        requestId: requestId.toString(),
      );
      await sendToClient(
        clientId,
        createErrorMessage(
          requestId: requestId,
          errorMessage: 'runId vazio ou ausente no payload',
          errorCode: ErrorCode.invalidRequest,
        ),
      );
      return;
    }

    LoggerService.infoWithContext(
      'ExecutionStatusMessageHandler: consultando runId=$runId',
      clientId: clientId,
      requestId: requestId.toString(),
    );

    final snapshot = _executionRegistry.getSnapshotByRunId(runId);
    if (snapshot != null) {
      await sendToClient(
        clientId,
        createExecutionStatusResponseMessage(
          requestId: requestId,
          runId: snapshot.runId,
          state: ExecutionState.running,
          serverTimeUtc: _clock(),
          scheduleId: snapshot.scheduleId,
          clientId: snapshot.clientId,
          startedAt: snapshot.startedAt,
        ),
      );
      return;
    }

    final q = _queueService?.findQueuedByRunId(runId);
    if (q != null) {
      final it = q.item;
      await sendToClient(
        clientId,
        createExecutionStatusResponseMessage(
          requestId: requestId,
          runId: runId,
          state: ExecutionState.queued,
          serverTimeUtc: _clock(),
          scheduleId: it.scheduleId,
          clientId: it.clientId,
          startedAt: it.queuedAt,
          queuedPosition: q.queuedPosition,
        ),
      );
      return;
    }

    final repo = _backupHistoryRepository;
    if (repo != null) {
      final res = await repo.getByRunId(runId);
      if (res.isSuccess()) {
        final h = res.getOrNull()!;
        final fromTerminal = _executionStateFromBackupHistory(h);
        if (fromTerminal != null) {
          await sendToClient(
            clientId,
            createExecutionStatusResponseMessage(
              requestId: requestId,
              runId: runId,
              state: fromTerminal,
              serverTimeUtc: _clock(),
              scheduleId: h.scheduleId,
              message: h.errorMessage,
            ),
          );
          return;
        }
        if (h.status == BackupStatus.running) {
          await sendToClient(
            clientId,
            createExecutionStatusResponseMessage(
              requestId: requestId,
              runId: runId,
              state: ExecutionState.running,
              serverTimeUtc: _clock(),
              scheduleId: h.scheduleId,
              startedAt: h.startedAt,
            ),
          );
          return;
        }
      }
    }

    await sendToClient(
      clientId,
      createExecutionStatusResponseMessage(
        requestId: requestId,
        runId: runId,
        state: ExecutionState.notFound,
        serverTimeUtc: _clock(),
        message: 'Execucao nao encontrada (registry, fila nem historico)',
      ),
    );
  }
}

/// `null` se o status for [BackupStatus.running] (tratado a parte no handler).
ExecutionState? _executionStateFromBackupHistory(BackupHistory h) {
  switch (h.status) {
    case BackupStatus.success:
      return ExecutionState.completed;
    case BackupStatus.error:
      return ExecutionState.failed;
    case BackupStatus.warning:
      final m = h.errorMessage ?? '';
      if (m.contains('cancelado')) {
        return ExecutionState.cancelled;
      }
      return ExecutionState.completed;
    case BackupStatus.running:
      return null;
  }
}
