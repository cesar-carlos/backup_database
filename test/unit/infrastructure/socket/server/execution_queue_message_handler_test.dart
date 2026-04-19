import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_message_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExecutionQueueMessageHandler', () {
    test(
      'sem provider injetado: responde fila vazia + maxQueueSize default',
      () async {
        final fixedNow = DateTime.utc(2026, 4, 19, 12);
        final handler = ExecutionQueueMessageHandler(clock: () => fixedNow);

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'c1',
          createExecutionQueueRequestMessage(),
          capture,
        );

        expect(sent, isNotNull);
        expect(sent!.header.type, MessageType.executionQueueResponse);
        final result = readExecutionQueueFromResponse(sent!);
        expect(result.queue, isEmpty);
        expect(result.totalQueued, 0);
        expect(result.maxQueueSize, 50, reason: 'M8 default');
        expect(result.serverTimeUtc, fixedNow);
        expect(result.isEmpty, isTrue);
      },
    );

    test(
      'maxQueueSize customizado e refletido na resposta',
      () async {
        final handler = ExecutionQueueMessageHandler(maxQueueSize: 10);
        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createExecutionQueueRequestMessage(), capture);

        final result = readExecutionQueueFromResponse(sent!);
        expect(result.maxQueueSize, 10);
      },
    );

    test(
      'provider retorna itens: handler ordena por queuedPosition asc',
      () async {
        // Provider intencionalmente embaralhado para validar ordenacao
        final handler = ExecutionQueueMessageHandler(
          queueProvider: () async => [
            QueuedExecution(
              runId: 'r3',
              scheduleId: 's3',
              queuedAt: DateTime.utc(2026, 4, 19, 11, 30),
              queuedPosition: 3,
            ),
            QueuedExecution(
              runId: 'r1',
              scheduleId: 's1',
              queuedAt: DateTime.utc(2026, 4, 19, 11),
              queuedPosition: 1,
              requestedBy: 'client-A',
            ),
            QueuedExecution(
              runId: 'r2',
              scheduleId: 's2',
              queuedAt: DateTime.utc(2026, 4, 19, 11, 15),
              queuedPosition: 2,
            ),
          ],
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createExecutionQueueRequestMessage(), capture);

        final result = readExecutionQueueFromResponse(sent!);
        expect(result.queue.length, 3);
        expect(result.queue[0].queuedPosition, 1);
        expect(result.queue[0].runId, 'r1');
        expect(result.queue[0].requestedBy, 'client-A');
        expect(result.queue[1].queuedPosition, 2);
        expect(result.queue[2].queuedPosition, 3);
        expect(result.totalQueued, 3);
      },
    );

    test(
      'provider lanca excecao -> responde fila vazia (fail-soft)',
      () async {
        final handler = ExecutionQueueMessageHandler(
          queueProvider: () async => throw Exception('db unavailable'),
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createExecutionQueueRequestMessage(), capture);

        expect(sent, isNotNull);
        expect(sent!.header.type, MessageType.executionQueueResponse);
        final result = readExecutionQueueFromResponse(sent!);
        // Fail-soft: cliente recebe fila vazia em vez de error
        expect(result.queue, isEmpty);
        expect(result.totalQueued, 0);
      },
    );

    test('ignora mensagens que nao sao executionQueueRequest', () async {
      final handler = ExecutionQueueMessageHandler();

      Message? sent;
      Future<void> capture(String c, Message m) async => sent = m;

      final notRequest = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 0),
        payload: const <String, dynamic>{},
        checksum: 0,
      );

      await handler.handle('c1', notRequest, capture);
      expect(sent, isNull);
    });

    test('serverTimeUtc usa o clock injetado', () async {
      final fixed = DateTime.utc(2026, 4, 19, 23, 59);
      final handler = ExecutionQueueMessageHandler(clock: () => fixed);

      Message? sent;
      Future<void> capture(String c, Message m) async => sent = m;

      await handler.handle('c1', createExecutionQueueRequestMessage(), capture);

      final result = readExecutionQueueFromResponse(sent!);
      expect(result.serverTimeUtc, fixed);
    });
  });
}
