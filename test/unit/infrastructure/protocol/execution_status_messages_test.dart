import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Execution status messages (PR-2 base / M2.3 complement)', () {
    test('createExecutionStatusRequestMessage carrega runId', () {
      final msg = createExecutionStatusRequestMessage(
        requestId: 1,
        runId: 'sched-1_uuid-aaa',
      );
      expect(msg.header.type, MessageType.executionStatusRequest);
      expect(msg.payload['runId'], 'sched-1_uuid-aaa');
      expect(isExecutionStatusRequestMessage(msg), isTrue);
      expect(getRunIdFromExecutionStatusRequest(msg), 'sched-1_uuid-aaa');
    });

    test('createExecutionStatusResponseMessage running com snapshot completo',
        () {
      final clock = DateTime.utc(2026, 4, 19, 12);
      final started = DateTime.utc(2026, 4, 19, 11, 30);
      final msg = createExecutionStatusResponseMessage(
        requestId: 2,
        runId: 'sched-1_uuid-aaa',
        state: ExecutionState.running,
        serverTimeUtc: clock,
        scheduleId: 'sched-1',
        clientId: 'client-X',
        startedAt: started,
      );

      expect(msg.header.type, MessageType.executionStatusResponse);
      expect(msg.payload['runId'], 'sched-1_uuid-aaa');
      expect(msg.payload['state'], 'running');
      expect(msg.payload['scheduleId'], 'sched-1');
      expect(msg.payload['clientId'], 'client-X');
      expect(msg.payload['startedAt'], '2026-04-19T11:30:00.000Z');
      expect(msg.payload['serverTimeUtc'], '2026-04-19T12:00:00.000Z');
      expect(msg.payload.containsKey('queuedPosition'), isFalse);
    });

    test('createExecutionStatusResponseMessage notFound minimal payload', () {
      final msg = createExecutionStatusResponseMessage(
        requestId: 1,
        runId: 'unknown-run',
        state: ExecutionState.notFound,
        serverTimeUtc: DateTime.utc(2026),
        message: 'Execucao nao encontrada',
      );
      expect(msg.payload['state'], 'notFound');
      expect(msg.payload.containsKey('scheduleId'), isFalse);
      expect(msg.payload.containsKey('clientId'), isFalse);
      expect(msg.payload.containsKey('startedAt'), isFalse);
      expect(msg.payload.containsKey('queuedPosition'), isFalse);
      expect(msg.payload['message'], 'Execucao nao encontrada');
    });

    test('createExecutionStatusResponseMessage queued com queuedPosition', () {
      final msg = createExecutionStatusResponseMessage(
        requestId: 1,
        runId: 'sched-2_uuid-bbb',
        state: ExecutionState.queued,
        serverTimeUtc: DateTime.utc(2026),
        scheduleId: 'sched-2',
        queuedPosition: 3,
      );
      expect(msg.payload['state'], 'queued');
      expect(msg.payload['queuedPosition'], 3);
    });

    test('readExecutionStatusFromResponse retorna snapshot tipado', () {
      final msg = createExecutionStatusResponseMessage(
        requestId: 1,
        runId: 'sched-1_uuid-aaa',
        state: ExecutionState.running,
        serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
        scheduleId: 'sched-1',
        clientId: 'client-X',
        startedAt: DateTime.utc(2026, 4, 19, 11, 30),
      );

      final result = readExecutionStatusFromResponse(msg);
      expect(result.runId, 'sched-1_uuid-aaa');
      expect(result.state, ExecutionState.running);
      expect(result.isActive, isTrue);
      expect(result.isTerminal, isFalse);
      expect(result.isNotFound, isFalse);
      expect(result.scheduleId, 'sched-1');
      expect(result.clientId, 'client-X');
      expect(result.startedAt, DateTime.utc(2026, 4, 19, 11, 30));
      expect(result.serverTimeUtc, DateTime.utc(2026, 4, 19, 12));
    });

    test(
      'readExecutionStatusFromResponse aplica defaults defensivos em payload vazio',
      () {
        final msg = Message(
          header: MessageHeader(
            type: MessageType.executionStatusResponse,
            length: 0,
            requestId: 1,
          ),
          payload: const <String, dynamic>{},
          checksum: 0,
        );

        final result = readExecutionStatusFromResponse(msg);
        // state ausente -> unknown (NAO notFound — distinguir
        // "endpoint nao implementado" de "execucao nao existe")
        expect(result.state, ExecutionState.unknown);
        expect(result.isActive, isFalse);
        expect(result.isTerminal, isFalse);
        expect(result.runId, isEmpty);
        expect(result.scheduleId, isNull);
        expect(result.clientId, isNull);
        expect(result.startedAt, isNull);
      },
    );

    test('ExecutionState.fromString tolera valor invalido', () {
      expect(ExecutionState.fromString('running'), ExecutionState.running);
      expect(ExecutionState.fromString('notFound'), ExecutionState.notFound);
      expect(ExecutionState.fromString('queued'), ExecutionState.queued);
      expect(ExecutionState.fromString('completed'), ExecutionState.completed);
      expect(ExecutionState.fromString('failed'), ExecutionState.failed);
      expect(ExecutionState.fromString('cancelled'), ExecutionState.cancelled);
      // Valor inesperado -> unknown
      expect(ExecutionState.fromString('xyz'), ExecutionState.unknown);
    });

    test('ExecutionState.isActive e isTerminal cobrem todos os estados', () {
      // Active: running + queued
      expect(ExecutionState.running.isActive, isTrue);
      expect(ExecutionState.queued.isActive, isTrue);
      expect(ExecutionState.notFound.isActive, isFalse);
      expect(ExecutionState.completed.isActive, isFalse);
      expect(ExecutionState.failed.isActive, isFalse);
      expect(ExecutionState.cancelled.isActive, isFalse);
      expect(ExecutionState.unknown.isActive, isFalse);

      // Terminal: completed + failed + cancelled
      expect(ExecutionState.completed.isTerminal, isTrue);
      expect(ExecutionState.failed.isTerminal, isTrue);
      expect(ExecutionState.cancelled.isTerminal, isTrue);
      expect(ExecutionState.running.isTerminal, isFalse);
      expect(ExecutionState.queued.isTerminal, isFalse);
      expect(ExecutionState.notFound.isTerminal, isFalse);
      expect(ExecutionState.unknown.isTerminal, isFalse);
    });

    test('readExecutionStatusFromResponse com startedAt invalido vira null',
        () {
      final msg = Message(
        header: MessageHeader(
          type: MessageType.executionStatusResponse,
          length: 0,
          requestId: 1,
        ),
        payload: const <String, dynamic>{
          'runId': 'r1',
          'state': 'running',
          'startedAt': 'not-a-date',
        },
        checksum: 0,
      );

      final result = readExecutionStatusFromResponse(msg);
      expect(result.startedAt, isNull);
    });
  });
}
