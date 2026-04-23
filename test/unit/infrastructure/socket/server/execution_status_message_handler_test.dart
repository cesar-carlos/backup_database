import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_service.dart';
import 'package:backup_database/infrastructure/socket/server/execution_status_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockBackupHistoryRepository extends Mock
    implements IBackupHistoryRepository {}

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

  group('ExecutionStatusMessageHandler PR-3c (fila e historico)', () {
    late _MockBackupHistoryRepository historyRepo;
    late ExecutionQueueService queue;
    late RemoteExecutionRegistry registry;
    late ExecutionStatusMessageHandler handler;
    final fixedNow = DateTime.utc(2026, 4, 23, 10);
    /// Clock fixo (UTC) na fila evita desvio local vs payload ISO em `startedAt`.
    final queueClock = DateTime.utc(2026, 4, 23, 9, 30);

    BackupHistory historyFixture({
      required String runId,
      required BackupStatus status,
      String? errorMessage,
    }) {
      final base = BackupHistory(
        databaseName: 'd',
        databaseType: 'sybase',
        backupPath: '/b',
        fileSize: 0,
        status: status,
        startedAt: DateTime.utc(2026),
        runId: runId,
        scheduleId: 'sched-h',
      );
      return errorMessage == null
          ? base
          : base.copyWith(errorMessage: errorMessage);
    }

    setUp(() {
      historyRepo = _MockBackupHistoryRepository();
      queue = ExecutionQueueService(clock: () => queueClock);
      registry = RemoteExecutionRegistry();
      handler = ExecutionStatusMessageHandler(
        executionRegistry: registry,
        queueService: queue,
        backupHistoryRepository: historyRepo,
        clock: () => fixedNow,
      );
    });

    test('fila: runId enfileirado responde queued com queuedPosition', () async {
      final item = await queue.tryEnqueue(
        scheduleId: 'sched-q',
        clientId: 'client-A',
        requestId: 1,
        requestedBy: 'client-A',
      );
      await queue.tryEnqueue(
        scheduleId: 'sched-b',
        clientId: 'c',
        requestId: 2,
        requestedBy: 'c',
      );
      final runId = item!.runId;
      expect(queue.findQueuedByRunId(runId)!.queuedPosition, 1);

      Message? sent;
      await handler.handle(
        'c1',
        createExecutionStatusRequestMessage(requestId: 1, runId: runId),
        (a, m) async => sent = m,
      );

      final r = readExecutionStatusFromResponse(sent!);
      expect(r.state, ExecutionState.queued);
      expect(r.queuedPosition, 1);
      expect(r.scheduleId, 'sched-q');
      expect(r.clientId, 'client-A');
      expect(r.startedAt, queueClock);
      expect(item.queuedAt, queueClock);
      expect(r.serverTimeUtc, fixedNow);
    });

    test('historico: success -> completed', () async {
      const runId = 'hist-ok-1';
      when(() => historyRepo.getByRunId(runId)).thenAnswer(
        (_) async => rd.Success(
          historyFixture(runId: runId, status: BackupStatus.success),
        ),
      );
      Message? sent;
      await handler.handle(
        'c1',
        createExecutionStatusRequestMessage(requestId: 1, runId: runId),
        (a, m) async => sent = m,
      );
      final r = readExecutionStatusFromResponse(sent!);
      expect(r.state, ExecutionState.completed);
      expect(r.scheduleId, 'sched-h');
    });

    test('historico: error -> failed e repassa message', () async {
      const runId = 'hist-err-1';
      when(() => historyRepo.getByRunId(runId)).thenAnswer(
        (_) async => rd.Success(
          historyFixture(
            runId: runId,
            status: BackupStatus.error,
            errorMessage: 'falhou backup',
          ),
        ),
      );
      Message? sent;
      await handler.handle(
        'c1',
        createExecutionStatusRequestMessage(requestId: 1, runId: runId),
        (a, m) async => sent = m,
      );
      final r = readExecutionStatusFromResponse(sent!);
      expect(r.state, ExecutionState.failed);
      expect(r.message, 'falhou backup');
    });

    test('historico: warning com cancelado no texto -> cancelled', () async {
      const runId = 'hist-can-1';
      when(() => historyRepo.getByRunId(runId)).thenAnswer(
        (_) async => rd.Success(
          historyFixture(
            runId: runId,
            status: BackupStatus.warning,
            errorMessage: 'operacao cancelado pelo usuario',
          ),
        ),
      );
      Message? sent;
      await handler.handle(
        'c1',
        createExecutionStatusRequestMessage(requestId: 1, runId: runId),
        (a, m) async => sent = m,
      );
      final r = readExecutionStatusFromResponse(sent!);
      expect(r.state, ExecutionState.cancelled);
    });

    test('historico: running (sem registry) -> running com startedAt do DB', () async {
      const runId = 'hist-run-1';
      final started = DateTime.utc(2026, 3, 15, 8);
      when(() => historyRepo.getByRunId(runId)).thenAnswer(
        (_) async => rd.Success(
          historyFixture(runId: runId, status: BackupStatus.running).copyWith(
            startedAt: started,
          ),
        ),
      );
      Message? sent;
      await handler.handle(
        'c1',
        createExecutionStatusRequestMessage(requestId: 1, runId: runId),
        (a, m) async => sent = m,
      );
      final r = readExecutionStatusFromResponse(sent!);
      expect(r.state, ExecutionState.running);
      expect(r.startedAt, started);
    });

    test('fila vence historico: mesmo runId enfileirado nao cai em completed do repo',
        () async {
      final enqueued = await queue.tryEnqueue(
        scheduleId: 'sched-both',
        clientId: 'cZ',
        requestId: 1,
        requestedBy: 'cZ',
      );
      final runId = enqueued!.runId;
      when(() => historyRepo.getByRunId(runId)).thenAnswer(
        (_) async => rd.Success(
          historyFixture(runId: runId, status: BackupStatus.success),
        ),
      );
      Message? sent;
      await handler.handle(
        'c1',
        createExecutionStatusRequestMessage(requestId: 1, runId: runId),
        (a, m) async => sent = m,
      );
      final r = readExecutionStatusFromResponse(sent!);
      expect(r.state, ExecutionState.queued);
      expect(r.queuedPosition, 1);
    });

    test('getByRunId sem sucesso: notFound', () async {
      const runId = 'nada-1';
      when(() => historyRepo.getByRunId(runId)).thenAnswer(
        (_) async => rd.Failure(Exception('not found')),
      );
      Message? sent;
      await handler.handle(
        'c1',
        createExecutionStatusRequestMessage(requestId: 1, runId: runId),
        (a, m) async => sent = m,
      );
      final r = readExecutionStatusFromResponse(sent!);
      expect(r.state, ExecutionState.notFound);
    });
  });
}
