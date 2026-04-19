import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Execution queue messages (PR-3b base)', () {
    test('createExecutionQueueRequestMessage tem payload vazio', () {
      final msg = createExecutionQueueRequestMessage(requestId: 1);
      expect(msg.header.type, MessageType.executionQueueRequest);
      expect(msg.payload, isEmpty);
      expect(isExecutionQueueRequestMessage(msg), isTrue);
    });

    test(
      'createExecutionQueueResponseMessage carrega queue + maxQueueSize',
      () {
        final clock = DateTime.utc(2026, 4, 19, 12);
        final queuedAt = DateTime.utc(2026, 4, 19, 11, 45);
        final msg = createExecutionQueueResponseMessage(
          requestId: 2,
          queue: [
            QueuedExecution(
              runId: 'sched-A_uuid-1',
              scheduleId: 'sched-A',
              queuedAt: queuedAt,
              queuedPosition: 1,
              requestedBy: 'client-X',
            ),
          ],
          maxQueueSize: 50,
          serverTimeUtc: clock,
        );

        expect(msg.header.type, MessageType.executionQueueResponse);
        expect(msg.payload['totalQueued'], 1);
        expect(msg.payload['maxQueueSize'], 50);
        expect(msg.payload['serverTimeUtc'], '2026-04-19T12:00:00.000Z');
        expect((msg.payload['queue'] as List).length, 1);
      },
    );

    test('QueuedExecution.toMap omite requestedBy quando null', () {
      final q1 = QueuedExecution(
        runId: 'r1',
        scheduleId: 's1',
        queuedAt: DateTime.utc(2026),
        queuedPosition: 1,
      );
      final map1 = q1.toMap();
      expect(map1.containsKey('requestedBy'), isFalse);

      final q2 = QueuedExecution(
        runId: 'r2',
        scheduleId: 's2',
        queuedAt: DateTime.utc(2026),
        queuedPosition: 2,
        requestedBy: 'client-Z',
      );
      expect(q2.toMap()['requestedBy'], 'client-Z');
    });

    test('readExecutionQueueFromResponse retorna snapshot tipado', () {
      final msg = createExecutionQueueResponseMessage(
        requestId: 1,
        queue: [
          QueuedExecution(
            runId: 'sched-A_uuid-1',
            scheduleId: 'sched-A',
            queuedAt: DateTime.utc(2026, 4, 19, 11),
            queuedPosition: 1,
            requestedBy: 'client-X',
          ),
          QueuedExecution(
            runId: 'sched-B_uuid-2',
            scheduleId: 'sched-B',
            queuedAt: DateTime.utc(2026, 4, 19, 11, 30),
            queuedPosition: 2,
          ),
        ],
        maxQueueSize: 50,
        serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
      );

      final result = readExecutionQueueFromResponse(msg);
      expect(result.queue.length, 2);
      expect(result.totalQueued, 2);
      expect(result.maxQueueSize, 50);
      expect(result.isEmpty, isFalse);
      expect(result.isFull, isFalse);
      expect(result.availableSlots, 48);
      expect(result.queue.first.runId, 'sched-A_uuid-1');
      expect(result.queue.first.requestedBy, 'client-X');
      expect(result.queue.last.requestedBy, isNull);
    });

    test(
      'readExecutionQueueFromResponse aplica defaults defensivos em payload vazio',
      () {
        final msg = Message(
          header: MessageHeader(
            type: MessageType.executionQueueResponse,
            length: 0,
            requestId: 1,
          ),
          payload: const <String, dynamic>{},
          checksum: 0,
        );

        final result = readExecutionQueueFromResponse(msg);
        expect(result.queue, isEmpty);
        expect(result.totalQueued, 0);
        // Default operacional do plano (M8)
        expect(result.maxQueueSize, 50);
        expect(result.isEmpty, isTrue);
        expect(result.isFull, isFalse);
        expect(result.availableSlots, 50);
      },
    );

    test('isFull retorna true quando totalQueued atinge maxQueueSize', () {
      final msg = createExecutionQueueResponseMessage(
        requestId: 1,
        queue: List.generate(
          5,
          (i) => QueuedExecution(
            runId: 'r$i',
            scheduleId: 's$i',
            queuedAt: DateTime.utc(2026),
            queuedPosition: i + 1,
          ),
        ),
        maxQueueSize: 5,
        serverTimeUtc: DateTime.utc(2026),
      );

      final result = readExecutionQueueFromResponse(msg);
      expect(result.totalQueued, 5);
      expect(result.maxQueueSize, 5);
      expect(result.isFull, isTrue);
      expect(result.availableSlots, 0);
    });

    test('queuedAt e serverTimeUtc sao serializados em ISO 8601 UTC', () {
      final localTime = DateTime(2026, 4, 19, 9, 30); // local
      final msg = createExecutionQueueResponseMessage(
        requestId: 1,
        queue: [
          QueuedExecution(
            runId: 'r1',
            scheduleId: 's1',
            queuedAt: localTime,
            queuedPosition: 1,
          ),
        ],
        maxQueueSize: 50,
        serverTimeUtc: localTime,
      );

      final raw = msg.payload['serverTimeUtc'] as String;
      expect(raw.endsWith('Z'), isTrue);
      final queueRaw = (msg.payload['queue'] as List).first as Map;
      expect((queueRaw['queuedAt'] as String).endsWith('Z'), isTrue);
    });

    test('QueuedExecution.fromMap aplica defaults defensivos', () {
      final q = QueuedExecution.fromMap(const <String, dynamic>{});
      expect(q.runId, isEmpty);
      expect(q.scheduleId, isEmpty);
      expect(q.queuedPosition, 0);
      expect(q.requestedBy, isNull);
      // queuedAt cai em now() — apenas confere que e UTC
      expect(q.queuedAt.isUtc, isTrue);
    });
  });
}
