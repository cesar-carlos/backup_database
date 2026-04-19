import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';

/// Responde `executionStatusRequest` com o estado atual de uma
/// execucao remota identificada por `runId`.
///
/// Implementa parte de PR-2 (`getExecutionStatus`) e complementa M2.3
/// (`runId` no contrato): cliente que recebeu `runId` em
/// `backupProgress`/`Complete`/`Failed` pode consultar status sob
/// demanda — util para reidratar UI apos reconexao ou polling
/// alternativo a stream.
///
/// Hoje (PR-1), o registry so observa execucoes em curso (`running`)
/// — implementacoes futuras (PR-3b com fila persistida, PR-3c com
/// historico) ampliarao para `queued`/`completed`/`failed`/`cancelled`.
/// Cliente ja preparado via [ExecutionState.unknown] como fallback.
class ExecutionStatusMessageHandler {
  ExecutionStatusMessageHandler({
    required RemoteExecutionRegistry executionRegistry,
    DateTime Function()? clock,
  })  : _executionRegistry = executionRegistry,
        _clock = clock ?? DateTime.now;

  final RemoteExecutionRegistry _executionRegistry;
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
    if (snapshot == null) {
      // Nao existe no registry: ja terminou (foi limpo) ou nunca
      // existiu. Cliente pode tentar baixar artefato (se aplicavel)
      // ou tratar como execucao perdida.
      await sendToClient(
        clientId,
        createExecutionStatusResponseMessage(
          requestId: requestId,
          runId: runId,
          state: ExecutionState.notFound,
          serverTimeUtc: _clock(),
          message: 'Execucao nao encontrada no registry ativo',
        ),
      );
      return;
    }

    // Execucao ativa no registry => running. Quando fila for
    // adicionada (PR-3b), `queued` virara um caso separado consultando
    // a tabela de fila.
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
  }
}
