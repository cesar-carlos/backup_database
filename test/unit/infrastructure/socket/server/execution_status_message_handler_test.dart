import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/execution_status_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExecutionStatusMessageHandler', () {
    late RemoteExecutionRegistry registry;
    late ExecutionStatusMessageHandler handler;
    final fixedNow = DateTime.utc(2026, 4, 19, 12);

    setUp(() {
      registry = RemoteExecutionRegistry();
      handler = ExecutionStatusMessageHandler(
        executionRegistry: registry,
        clock: () => fixedNow,
      );
    });

    test(
      'runId existente no registry -> responde running com snapshot',
      () async {
        final runId = registry.generateRunId('sched-X');
        registry.register(
          runId: runId,
          scheduleId: 'sched-X',
          clientId: 'client-A',
          requestId: 99,
          sendToClient: (clientId, msg) async {},
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'client-X',
          createExecutionStatusRequestMessage(requestId: 1, runId: runId),
          capture,
        );

        expect(sent, isNotNull);
        expect(sent!.header.type, MessageType.executionStatusResponse);
        final result = readExecutionStatusFromResponse(sent!);
        expect(result.runId, runId);
        expect(result.state, ExecutionState.running);
        expect(result.scheduleId, 'sched-X');
        expect(result.clientId, 'client-A');
        expect(result.startedAt, isNotNull);
        expect(result.serverTimeUtc, fixedNow);
      },
    );

    test(
      'runId desconhecido -> responde notFound (nao crash)',
      () async {
        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'client-X',
          createExecutionStatusRequestMessage(
            requestId: 1,
            runId: 'never-existed',
          ),
          capture,
        );

        expect(sent, isNotNull);
        final result = readExecutionStatusFromResponse(sent!);
        expect(result.state, ExecutionState.notFound);
        expect(result.runId, 'never-existed');
        expect(result.scheduleId, isNull);
        expect(result.message, contains('nao encontrada'));
      },
    );

    test('runId vazio -> responde error padronizado', () async {
      Message? sent;
      Future<void> capture(String c, Message m) async => sent = m;

      await handler.handle(
        'client-X',
        createExecutionStatusRequestMessage(requestId: 1, runId: ''),
        capture,
      );

      expect(sent, isNotNull);
      expect(sent!.header.type, MessageType.error);
      expect(getErrorCodeFromMessage(sent!), ErrorCode.invalidRequest);
      expect(getErrorFromMessage(sent!), contains('runId'));
    });

    test('ignora mensagens que nao sao executionStatusRequest', () async {
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

    test(
      'apos unregister, runId previamente conhecido vira notFound',
      () async {
        final runId = registry.generateRunId('sched-Y');
        registry.register(
          runId: runId,
          scheduleId: 'sched-Y',
          clientId: 'client-B',
          requestId: 1,
          sendToClient: (clientId, msg) async {},
        );

        // Registry esquece o contexto (ex.: backup terminou e
        // ScheduleMessageHandler chamou unregister)
        registry.unregister(runId);

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'c1',
          createExecutionStatusRequestMessage(requestId: 2, runId: runId),
          capture,
        );

        final result = readExecutionStatusFromResponse(sent!);
        expect(result.state, ExecutionState.notFound);
      },
    );

    test('serverTimeUtc usa o clock injetado', () async {
      final runId = registry.generateRunId('sched-Z');
      registry.register(
        runId: runId,
        scheduleId: 'sched-Z',
        clientId: 'c1',
        requestId: 1,
        sendToClient: (clientId, msg) async {},
      );

      Message? sent;
      Future<void> capture(String c, Message m) async => sent = m;

      await handler.handle(
        'c1',
        createExecutionStatusRequestMessage(requestId: 1, runId: runId),
        capture,
      );

      final result = readExecutionStatusFromResponse(sent!);
      expect(result.serverTimeUtc, fixedNow);
    });
  });
}
