import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart'
    show SendToClient;

/// Provider assincrono que retorna o snapshot atual da fila de
/// execucoes. Wirings em PR-1 retornam lista vazia (mutex global de
/// 1 backup ja rejeita disparo concorrente). Em PR-3b, sera cabeado
/// com query na tabela de fila persistida.
typedef QueueProvider = Future<List<QueuedExecution>> Function();

/// Responde `executionQueueRequest` com o snapshot atual da fila de
/// execucoes remotas aguardando slot livre.
///
/// Implementa parte de PR-3b (fila com `getExecutionQueue`); endpoint
/// disponivel desde ja para que clientes preparem a UI sem esperar a
/// fila persistida ser implementada — ate la, sempre devolve lista
/// vazia.
///
/// `maxQueueSize` reflete o default operacional do plano (M8: 50).
/// Quando configuracao formal for adicionada, basta cabear via
/// construtor — handler nao precisa mudar.
class ExecutionQueueMessageHandler {
  ExecutionQueueMessageHandler({
    QueueProvider? queueProvider,
    int maxQueueSize = 50,
    DateTime Function()? clock,
  })  : _queueProvider = queueProvider ?? _emptyQueue,
        _maxQueueSize = maxQueueSize,
        _clock = clock ?? DateTime.now;

  final QueueProvider _queueProvider;
  final int _maxQueueSize;
  final DateTime Function() _clock;

  static Future<List<QueuedExecution>> _emptyQueue() async =>
      const <QueuedExecution>[];

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    if (!isExecutionQueueRequestMessage(message)) return;

    final requestId = message.header.requestId;
    LoggerService.infoWithContext(
      'ExecutionQueueMessageHandler: respondendo queue snapshot',
      clientId: clientId,
      requestId: requestId.toString(),
    );

    try {
      final queue = await _queueProvider();
      // Defesa: ordena por queuedPosition ascendente para garantir
      // ordem estavel mesmo se o provider retornar embaralhado (ex.:
      // query de banco sem ORDER BY explicito).
      final sorted = [...queue]
        ..sort((a, b) => a.queuedPosition.compareTo(b.queuedPosition));
      await sendToClient(
        clientId,
        createExecutionQueueResponseMessage(
          requestId: requestId,
          queue: sorted,
          maxQueueSize: _maxQueueSize,
          serverTimeUtc: _clock(),
        ),
      );
    } on Object catch (e, st) {
      LoggerService.warning(
        'ExecutionQueueMessageHandler: provider lancou excecao: $e',
        e,
        st,
      );
      // Fail-soft: responde com fila vazia em vez de error. Cliente
      // continua usavel; operador detecta via metricas/logs.
      await sendToClient(
        clientId,
        createExecutionQueueResponseMessage(
          requestId: requestId,
          queue: const <QueuedExecution>[],
          maxQueueSize: _maxQueueSize,
          serverTimeUtc: _clock(),
        ),
      );
    }
  }
}
