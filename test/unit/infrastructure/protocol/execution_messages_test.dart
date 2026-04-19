import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/execution_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('startBackupRequest', () {
    test('payload contem scheduleId obrigatorio', () {
      final msg = createStartBackupRequest(scheduleId: 'sch-1', requestId: 7);
      expect(msg.header.type, MessageType.startBackupRequest);
      expect(msg.header.requestId, 7);
      expect(msg.payload['scheduleId'], 'sch-1');
      expect(msg.payload.containsKey('idempotencyKey'), isFalse);
    });

    test('inclui idempotencyKey quando informada', () {
      final msg = createStartBackupRequest(
        scheduleId: 'x',
        idempotencyKey: 'idem-1',
      );
      expect(msg.payload['idempotencyKey'], 'idem-1');
    });

    test('omite idempotencyKey quando vazia', () {
      final msg = createStartBackupRequest(
        scheduleId: 'x',
        idempotencyKey: '',
      );
      expect(msg.payload.containsKey('idempotencyKey'), isFalse);
    });

    test('rejeita scheduleId vazio', () {
      expect(
        () => createStartBackupRequest(scheduleId: ''),
        throwsArgumentError,
      );
    });
  });

  group('startBackupResponse', () {
    test('aceite assincrono (running) -> statusCode 202', () {
      final msg = createStartBackupResponse(
        requestId: 1,
        runId: 'r1',
        state: ExecutionState.running,
        scheduleId: 'sch-1',
        serverTimeUtc: DateTime.utc(2026),
      );
      expect(msg.payload['statusCode'], StatusCodes.accepted);
      expect(msg.payload['success'], isTrue);
      expect(msg.payload['runId'], 'r1');
      expect(msg.payload['state'], 'running');
      expect(msg.payload['scheduleId'], 'sch-1');
    });

    test('queued tambem -> 202', () {
      final msg = createStartBackupResponse(
        requestId: 1,
        runId: 'r1',
        state: ExecutionState.queued,
        scheduleId: 'sch-1',
        serverTimeUtc: DateTime.utc(2026),
        queuePosition: 3,
      );
      expect(msg.payload['statusCode'], StatusCodes.accepted);
      expect(msg.payload['queuePosition'], 3);
    });

    test('completed (cache de idempotencia) -> 200', () {
      // Cliente reusou idempotencyKey de execucao ja concluida —
      // servidor pode retornar state=completed sincronamente sem
      // disparar nova execucao. Codigo deve refletir isso (200 OK).
      final msg = createStartBackupResponse(
        requestId: 1,
        runId: 'r1',
        state: ExecutionState.completed,
        scheduleId: 'sch-1',
        serverTimeUtc: DateTime.utc(2026),
      );
      expect(msg.payload['statusCode'], StatusCodes.ok);
    });

    test('round-trip via readStartBackupResponse', () {
      final msg = createStartBackupResponse(
        requestId: 1,
        runId: 'r-xyz',
        state: ExecutionState.running,
        scheduleId: 'sch-1',
        serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
        message: 'iniciado',
      );
      final parsed = readStartBackupResponse(msg);
      expect(parsed.runId, 'r-xyz');
      expect(parsed.state, ExecutionState.running);
      expect(parsed.scheduleId, 'sch-1');
      expect(parsed.message, 'iniciado');
      expect(parsed.isAccepted, isTrue);
      expect(parsed.isRunning, isTrue);
      expect(parsed.isQueued, isFalse);
    });

    test('parsing defensivo: state desconhecido vira unknown', () {
      final msg = createStartBackupResponse(
        requestId: 1,
        runId: 'r1',
        state: ExecutionState.running,
        scheduleId: 'sch-1',
        serverTimeUtc: DateTime.utc(2026),
      );
      msg.payload['state'] = 'estado-fantasma';
      final parsed = readStartBackupResponse(msg);
      expect(parsed.state, ExecutionState.unknown);
    });
  });

  group('cancelBackupRequest', () {
    test('por runId', () {
      final msg = createCancelBackupRequest(runId: 'r1', requestId: 5);
      expect(msg.header.type, MessageType.cancelBackupRequest);
      expect(msg.payload['runId'], 'r1');
      expect(msg.payload.containsKey('scheduleId'), isFalse);
    });

    test('por scheduleId', () {
      final msg = createCancelBackupRequest(scheduleId: 's1');
      expect(msg.payload['scheduleId'], 's1');
      expect(msg.payload.containsKey('runId'), isFalse);
    });

    test('XOR: rejeita ambos', () {
      expect(
        () => createCancelBackupRequest(runId: 'r', scheduleId: 's'),
        throwsArgumentError,
      );
    });

    test('XOR: rejeita nenhum', () {
      expect(() => createCancelBackupRequest(), throwsArgumentError);
    });
  });

  group('cancelBackupResponse', () {
    test('cancelled -> 200', () {
      final msg = createCancelBackupResponse(
        requestId: 1,
        state: ExecutionState.cancelled,
        serverTimeUtc: DateTime.utc(2026),
        runId: 'r1',
      );
      expect(msg.payload['statusCode'], 200);
      expect(msg.payload['state'], 'cancelled');
    });

    test('noActiveExecution -> 409', () {
      final msg = createCancelBackupResponse(
        requestId: 1,
        state: ExecutionState.notFound,
        serverTimeUtc: DateTime.utc(2026),
        runId: 'r1',
        errorCode: ErrorCode.noActiveExecution,
      );
      expect(msg.payload['statusCode'], StatusCodes.conflict);
      expect(msg.payload['errorCode'], 'NO_ACTIVE_EXECUTION');
    });

    test('round-trip', () {
      final msg = createCancelBackupResponse(
        requestId: 1,
        state: ExecutionState.cancelled,
        serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
        runId: 'r1',
        scheduleId: 's1',
        message: 'sinalizado',
      );
      final parsed = readCancelBackupResponse(msg);
      expect(parsed.state, ExecutionState.cancelled);
      expect(parsed.runId, 'r1');
      expect(parsed.scheduleId, 's1');
      expect(parsed.message, 'sinalizado');
      expect(parsed.isCancelled, isTrue);
    });

    test('hasNoActiveExecution helper', () {
      final msg = createCancelBackupResponse(
        requestId: 1,
        state: ExecutionState.notFound,
        serverTimeUtc: DateTime.utc(2026),
        errorCode: ErrorCode.noActiveExecution,
      );
      final parsed = readCancelBackupResponse(msg);
      expect(parsed.hasNoActiveExecution, isTrue);
      expect(parsed.isCancelled, isFalse);
    });
  });
}
