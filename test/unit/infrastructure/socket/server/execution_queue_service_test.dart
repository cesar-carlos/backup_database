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

    test('tryEnqueue insere com runId no formato scheduleId_uuid', () {
      final svc = ExecutionQueueService();
      final item = svc.tryEnqueue(
        scheduleId: 's-1',
        clientId: 'c1',
        requestId: 1,
        requestedBy: 'c1',
      )!;
      expect(item.scheduleId, 's-1');
      expect(item.runId, startsWith('s-1_'));
      expect(svc.queueSize, 1);
      expect(svc.isScheduleQueued('s-1'), isTrue);
    });

    test('FIFO: dequeue na ordem de insercao', () {
      final svc = ExecutionQueueService();
      svc.tryEnqueue(scheduleId: 'a', clientId: 'c', requestId: 1, requestedBy: 'c');
      svc.tryEnqueue(scheduleId: 'b', clientId: 'c', requestId: 2, requestedBy: 'c');
      svc.tryEnqueue(scheduleId: 'c', clientId: 'c', requestId: 3, requestedBy: 'c');

      expect(svc.dequeue()!.scheduleId, 'a');
      expect(svc.dequeue()!.scheduleId, 'b');
      expect(svc.dequeue()!.scheduleId, 'c');
      expect(svc.dequeue(), isNull);
    });

    test('dedup por scheduleId: 2a tentativa do mesmo schedule retorna null', () {
      final svc = ExecutionQueueService();
      final first = svc.tryEnqueue(
        scheduleId: 's', clientId: 'c', requestId: 1, requestedBy: 'c',
      );
      final second = svc.tryEnqueue(
        scheduleId: 's', clientId: 'c', requestId: 2, requestedBy: 'c',
      );
      expect(first, isNotNull);
      expect(second, isNull);
      expect(svc.queueSize, 1);
    });

    test('apos dequeue, schedule pode ser re-enfileirado', () {
      final svc = ExecutionQueueService();
      svc.tryEnqueue(scheduleId: 's', clientId: 'c', requestId: 1, requestedBy: 'c');
      svc.dequeue();
      final retried = svc.tryEnqueue(
        scheduleId: 's', clientId: 'c', requestId: 2, requestedBy: 'c',
      );
      expect(retried, isNotNull);
    });

    test('maxQueueSize: rejeita alem do limite', () {
      final svc = ExecutionQueueService(maxQueueSize: 3);
      for (var i = 0; i < 3; i++) {
        expect(
          svc.tryEnqueue(
            scheduleId: 's-$i', clientId: 'c', requestId: i, requestedBy: 'c',
          ),
          isNotNull,
        );
      }
      expect(svc.isFull, isTrue);
      final overflow = svc.tryEnqueue(
        scheduleId: 's-4', clientId: 'c', requestId: 4, requestedBy: 'c',
      );
      expect(overflow, isNull);
    });

    test('snapshot retorna lista ordenada com queuedPosition 1-based', () {
      final svc = ExecutionQueueService();
      svc.tryEnqueue(scheduleId: 'a', clientId: 'c', requestId: 1, requestedBy: 'c');
      svc.tryEnqueue(scheduleId: 'b', clientId: 'c', requestId: 2, requestedBy: 'c');

      final snap = svc.snapshot();
      expect(snap, hasLength(2));
      expect(snap[0].scheduleId, 'a');
      expect(snap[0].queuedPosition, 1);
      expect(snap[1].scheduleId, 'b');
      expect(snap[1].queuedPosition, 2);
    });

    test('removeByRunId remove o item correto', () {
      final svc = ExecutionQueueService();
      final a = svc.tryEnqueue(
        scheduleId: 'a', clientId: 'c', requestId: 1, requestedBy: 'c',
      )!;
      svc.tryEnqueue(scheduleId: 'b', clientId: 'c', requestId: 2, requestedBy: 'c');

      final removed = svc.removeByRunId(a.runId);
      expect(removed, isTrue);
      expect(svc.queueSize, 1);
      expect(svc.isScheduleQueued('a'), isFalse);
      expect(svc.isScheduleQueued('b'), isTrue);
    });

    test('removeByRunId retorna false para runId desconhecido', () {
      final svc = ExecutionQueueService();
      svc.tryEnqueue(scheduleId: 's', clientId: 'c', requestId: 1, requestedBy: 'c');
      expect(svc.removeByRunId('runId-fake'), isFalse);
      expect(svc.queueSize, 1);
    });

    test('clear esvazia a fila e o set de schedules', () {
      final svc = ExecutionQueueService();
      svc.tryEnqueue(scheduleId: 'a', clientId: 'c', requestId: 1, requestedBy: 'c');
      svc.tryEnqueue(scheduleId: 'b', clientId: 'c', requestId: 2, requestedBy: 'c');
      svc.clear();
      expect(svc.isEmpty, isTrue);
      expect(svc.isScheduleQueued('a'), isFalse);
    });

    test('hasActive setter expoe estado', () {
      final svc = ExecutionQueueService();
      expect(svc.hasActive, isFalse);
      svc.hasActive = true;
      expect(svc.hasActive, isTrue);
    });
  });
}
