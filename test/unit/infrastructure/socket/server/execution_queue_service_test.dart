import 'package:backup_database/infrastructure/socket/server/execution_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExecutionQueueService', () {
    test('vazio inicialmente', () {
      final svc = ExecutionQueueService();
      expect(svc.isEmpty, isTrue);
      expect(svc.queueSize, 0);
      expect(svc.isFull, isFalse);
      expect(svc.maxQueueSize, 50);
    });

    test('tryEnqueue insere com runId no formato scheduleId_uuid', () async {
      final svc = ExecutionQueueService();
      final item = await svc.tryEnqueue(
        scheduleId: 's-1',
        clientId: 'c1',
        requestId: 1,
        requestedBy: 'c1',
      );
      expect(item, isNotNull);
      expect(item!.scheduleId, 's-1');
      expect(item.runId, startsWith('s-1_'));
      expect(svc.queueSize, 1);
      expect(svc.isScheduleQueued('s-1'), isTrue);
    });

    test('FIFO: dequeue na ordem de insercao', () async {
      final svc = ExecutionQueueService();
      await svc.tryEnqueue(
        scheduleId: 'a',
        clientId: 'c',
        requestId: 1,
        requestedBy: 'c',
      );
      await svc.tryEnqueue(
        scheduleId: 'b',
        clientId: 'c',
        requestId: 2,
        requestedBy: 'c',
      );
      await svc.tryEnqueue(
        scheduleId: 'c',
        clientId: 'c',
        requestId: 3,
        requestedBy: 'c',
      );

      expect((await svc.dequeue())!.scheduleId, 'a');
      expect((await svc.dequeue())!.scheduleId, 'b');
      expect((await svc.dequeue())!.scheduleId, 'c');
      expect(await svc.dequeue(), isNull);
    });

    test('dedup por scheduleId: 2a tentativa do mesmo schedule retorna null',
        () async {
      final svc = ExecutionQueueService();
      final first = await svc.tryEnqueue(
        scheduleId: 's',
        clientId: 'c',
        requestId: 1,
        requestedBy: 'c',
      );
      final second = await svc.tryEnqueue(
        scheduleId: 's',
        clientId: 'c',
        requestId: 2,
        requestedBy: 'c',
      );
      expect(first, isNotNull);
      expect(second, isNull);
      expect(svc.queueSize, 1);
    });

    test('apos dequeue, schedule pode ser re-enfileirado', () async {
      final svc = ExecutionQueueService();
      await svc.tryEnqueue(
        scheduleId: 's',
        clientId: 'c',
        requestId: 1,
        requestedBy: 'c',
      );
      await svc.dequeue();
      final retried = await svc.tryEnqueue(
        scheduleId: 's',
        clientId: 'c',
        requestId: 2,
        requestedBy: 'c',
      );
      expect(retried, isNotNull);
    });

    test('maxQueueSize: rejeita alem do limite', () async {
      final svc = ExecutionQueueService(maxQueueSize: 3);
      for (var i = 0; i < 3; i++) {
        expect(
          await svc.tryEnqueue(
            scheduleId: 's-$i',
            clientId: 'c',
            requestId: i,
            requestedBy: 'c',
          ),
          isNotNull,
        );
      }
      expect(svc.isFull, isTrue);
      final overflow = await svc.tryEnqueue(
        scheduleId: 's-4',
        clientId: 'c',
        requestId: 4,
        requestedBy: 'c',
      );
      expect(overflow, isNull);
    });

    test('snapshot retorna lista ordenada com queuedPosition 1-based', () async {
      final svc = ExecutionQueueService();
      await svc.tryEnqueue(
        scheduleId: 'a',
        clientId: 'c',
        requestId: 1,
        requestedBy: 'c',
      );
      await svc.tryEnqueue(
        scheduleId: 'b',
        clientId: 'c',
        requestId: 2,
        requestedBy: 'c',
      );

      final snap = svc.snapshot();
      expect(snap, hasLength(2));
      expect(snap[0].scheduleId, 'a');
      expect(snap[0].queuedPosition, 1);
      expect(snap[1].scheduleId, 'b');
      expect(snap[1].queuedPosition, 2);
    });

    test('removeByRunId remove o item correto', () async {
      final svc = ExecutionQueueService();
      final a = await svc.tryEnqueue(
        scheduleId: 'a',
        clientId: 'c',
        requestId: 1,
        requestedBy: 'c',
      );
      await svc.tryEnqueue(
        scheduleId: 'b',
        clientId: 'c',
        requestId: 2,
        requestedBy: 'c',
      );

      final removed = await svc.removeByRunId(a!.runId);
      expect(removed, isTrue);
      expect(svc.queueSize, 1);
      expect(svc.isScheduleQueued('a'), isFalse);
      expect(svc.isScheduleQueued('b'), isTrue);
    });

    test('removeByRunId retorna false para runId desconhecido', () async {
      final svc = ExecutionQueueService();
      await svc.tryEnqueue(
        scheduleId: 's',
        clientId: 'c',
        requestId: 1,
        requestedBy: 'c',
      );
      expect(await svc.removeByRunId('runId-fake'), isFalse);
      expect(svc.queueSize, 1);
    });

    test('clear esvazia a fila e o set de schedules', () async {
      final svc = ExecutionQueueService();
      await svc.tryEnqueue(
        scheduleId: 'a',
        clientId: 'c',
        requestId: 1,
        requestedBy: 'c',
      );
      await svc.tryEnqueue(
        scheduleId: 'b',
        clientId: 'c',
        requestId: 2,
        requestedBy: 'c',
      );
      await svc.clear();
      expect(svc.isEmpty, isTrue);
      expect(svc.isScheduleQueued('a'), isFalse);
    });

    test('hasActive setter expoe estado', () {
      final svc = ExecutionQueueService();
      expect(svc.hasActive, isFalse);
      svc.hasActive = true;
      expect(svc.hasActive, isTrue);
    });

    test('findQueuedByRunId retorna item e posicao 1-based', () async {
      final svc = ExecutionQueueService();
      final first = await svc.tryEnqueue(
        scheduleId: 'a',
        clientId: 'c',
        requestId: 1,
        requestedBy: 'c',
      );
      final second = await svc.tryEnqueue(
        scheduleId: 'b',
        clientId: 'c',
        requestId: 2,
        requestedBy: 'c',
      );

      final f = svc.findQueuedByRunId(first!.runId);
      final s = svc.findQueuedByRunId(second!.runId);
      expect(f?.queuedPosition, 1);
      expect(f?.item.runId, first.runId);
      expect(s?.queuedPosition, 2);
      expect(svc.findQueuedByRunId('desconhecido'), isNull);
    });
  });
}
