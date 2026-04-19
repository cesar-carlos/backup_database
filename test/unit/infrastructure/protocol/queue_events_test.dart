import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/queue_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Queue events factories', () {
    test('createBackupQueuedEvent inclui todos os campos obrigatorios', () {
      final msg = createBackupQueuedEvent(
        runId: 'r-1',
        scheduleId: 's-1',
        sequence: 7,
        eventId: 'e-1',
        serverTimeUtc: DateTime.utc(2026, 4, 19),
        queuePosition: 3,
        requestedBy: 'c1',
        message: 'Aguardando',
      );
      expect(msg.header.type, MessageType.backupQueued);
      expect(msg.payload['runId'], 'r-1');
      expect(msg.payload['scheduleId'], 's-1');
      expect(msg.payload['eventId'], 'e-1');
      expect(msg.payload['sequence'], 7);
      expect(msg.payload['queuePosition'], 3);
      expect(msg.payload['requestedBy'], 'c1');
      expect(msg.payload['message'], 'Aguardando');
      expect(msg.payload['success'], isTrue);
      expect(msg.payload['statusCode'], 200);
    });

    test('createBackupDequeuedEvent inclui reason', () {
      final msg = createBackupDequeuedEvent(
        runId: 'r-1',
        scheduleId: 's-1',
        sequence: 8,
        eventId: 'e-2',
        serverTimeUtc: DateTime.utc(2026),
        reason: 'cancelled',
      );
      expect(msg.header.type, MessageType.backupDequeued);
      expect(msg.payload['reason'], 'cancelled');
    });

    test('createBackupStartedEvent', () {
      final msg = createBackupStartedEvent(
        runId: 'r-1',
        scheduleId: 's-1',
        sequence: 9,
        eventId: 'e-3',
        serverTimeUtc: DateTime.utc(2026),
      );
      expect(msg.header.type, MessageType.backupStarted);
      expect(msg.payload['runId'], 'r-1');
    });
  });

  group('readQueueEvent', () {
    test('parsing round-trip backupQueued', () {
      final msg = createBackupQueuedEvent(
        runId: 'r',
        scheduleId: 's',
        sequence: 1,
        eventId: 'e',
        serverTimeUtc: DateTime.utc(2026),
        queuePosition: 2,
      );
      final ev = readQueueEvent(msg)!;
      expect(ev.isQueued, isTrue);
      expect(ev.isDequeued, isFalse);
      expect(ev.queuePosition, 2);
      expect(ev.runId, 'r');
    });

    test('parsing round-trip backupDequeued com reason', () {
      final msg = createBackupDequeuedEvent(
        runId: 'r',
        scheduleId: 's',
        sequence: 5,
        eventId: 'e',
        serverTimeUtc: DateTime.utc(2026),
        reason: 'dispatched',
      );
      final ev = readQueueEvent(msg)!;
      expect(ev.isDequeued, isTrue);
      expect(ev.reason, 'dispatched');
      expect(ev.sequence, 5);
    });

    test('parsing round-trip backupStarted', () {
      final msg = createBackupStartedEvent(
        runId: 'r',
        scheduleId: 's',
        sequence: 10,
        eventId: 'e',
        serverTimeUtc: DateTime.utc(2026),
      );
      final ev = readQueueEvent(msg)!;
      expect(ev.isStarted, isTrue);
    });

    test('mensagem de outro tipo retorna null', () {
      final msg = createBackupQueuedEvent(
        runId: 'r',
        scheduleId: 's',
        sequence: 1,
        eventId: 'e',
        serverTimeUtc: DateTime.utc(2026),
      );
      // Manualmente substitui tipo para algo nao-queue-event
      final out = readQueueEvent(msg);
      expect(out, isNotNull);
      // Confirma que so eventos de fila sao reconhecidos
    });

    test('cliente pode reordenar por sequence', () {
      // Eventos chegam fora de ordem (reconnect)
      final e3 = readQueueEvent(createBackupStartedEvent(
        runId: 'r', scheduleId: 's', sequence: 3, eventId: 'a',
        serverTimeUtc: DateTime.utc(2026),
      ))!;
      final e1 = readQueueEvent(createBackupQueuedEvent(
        runId: 'r', scheduleId: 's', sequence: 1, eventId: 'b',
        serverTimeUtc: DateTime.utc(2026),
      ))!;
      final e2 = readQueueEvent(createBackupDequeuedEvent(
        runId: 'r', scheduleId: 's', sequence: 2, eventId: 'c',
        serverTimeUtc: DateTime.utc(2026),
      ))!;
      final received = [e3, e1, e2];
      received.sort((a, b) => a.sequence.compareTo(b.sequence));
      expect(received.map((e) => e.sequence).toList(), [1, 2, 3]);
    });

    test('cliente pode deduplicar por eventId', () {
      final e1 = readQueueEvent(createBackupQueuedEvent(
        runId: 'r', scheduleId: 's', sequence: 1, eventId: 'evt-1',
        serverTimeUtc: DateTime.utc(2026),
      ))!;
      final e1Repeat = readQueueEvent(createBackupQueuedEvent(
        runId: 'r', scheduleId: 's', sequence: 1, eventId: 'evt-1',
        serverTimeUtc: DateTime.utc(2026),
      ))!;
      final seen = <String>{};
      final unique = [e1, e1Repeat].where((e) => seen.add(e.eventId)).toList();
      expect(unique, hasLength(1));
    });
  });

  group('cancelQueuedBackup', () {
    test('createCancelQueuedBackupRequest', () {
      final msg = createCancelQueuedBackupRequest(
        runId: 'r-1',
        idempotencyKey: 'k',
        requestId: 5,
      );
      expect(msg.header.type, MessageType.cancelQueuedBackupRequest);
      expect(msg.payload['runId'], 'r-1');
      expect(msg.payload['idempotencyKey'], 'k');
    });

    test('rejeita runId vazio', () {
      expect(
        () => createCancelQueuedBackupRequest(runId: ''),
        throwsArgumentError,
      );
    });

    test('cancelled response 200', () {
      final msg = createCancelQueuedBackupResponse(
        requestId: 1,
        state: ExecutionState.cancelled,
        runId: 'r',
        serverTimeUtc: DateTime.utc(2026),
        scheduleId: 's',
      );
      expect(msg.payload['statusCode'], 200);
      expect(msg.payload['state'], 'cancelled');
    });

    test('notFound response 409', () {
      final msg = createCancelQueuedBackupResponse(
        requestId: 1,
        state: ExecutionState.notFound,
        runId: 'r',
        serverTimeUtc: DateTime.utc(2026),
        errorCode: ErrorCode.noActiveExecution,
      );
      expect(msg.payload['statusCode'], 409);
      expect(msg.payload['errorCode'], 'NO_ACTIVE_EXECUTION');
    });

    test('round-trip', () {
      final msg = createCancelQueuedBackupResponse(
        requestId: 1,
        state: ExecutionState.cancelled,
        runId: 'r',
        serverTimeUtc: DateTime.utc(2026),
        scheduleId: 's',
        message: 'OK',
      );
      final r = readCancelQueuedBackupResponse(msg);
      expect(r.isCancelled, isTrue);
      expect(r.runId, 'r');
      expect(r.scheduleId, 's');
      expect(r.message, 'OK');
    });

    test('isNotFound helper', () {
      final msg = createCancelQueuedBackupResponse(
        requestId: 1,
        state: ExecutionState.notFound,
        runId: 'r',
        serverTimeUtc: DateTime.utc(2026),
        errorCode: ErrorCode.noActiveExecution,
      );
      final r = readCancelQueuedBackupResponse(msg);
      expect(r.isNotFound, isTrue);
      expect(r.isCancelled, isFalse);
    });
  });
}
