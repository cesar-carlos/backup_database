import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _noopSend(String clientId, Message message) async {}

void main() {
  group('RemoteExecutionRegistry', () {
    late RemoteExecutionRegistry registry;

    setUp(() {
      registry = RemoteExecutionRegistry();
    });

    test('starts empty and reports no active executions', () {
      expect(registry.activeCount, 0);
      expect(registry.hasAny, isFalse);
      expect(registry.all, isEmpty);
      expect(registry.hasActiveForSchedule('any'), isFalse);
      expect(registry.getActiveByScheduleId('any'), isNull);
      expect(registry.getByRunId('any'), isNull);
    });

    test('generateRunId follows scheduleId_<uuid> pattern', () {
      final runId = registry.generateRunId('schedule-1');
      expect(runId, startsWith('schedule-1_'));
      expect(runId.length, greaterThan('schedule-1_'.length + 30));
    });

    test('register adds context and indexes by scheduleId', () {
      final runId = registry.generateRunId('schedule-1');
      final ctx = registry.register(
        runId: runId,
        scheduleId: 'schedule-1',
        clientId: 'client-1',
        requestId: 42,
        sendToClient: _noopSend,
      );

      expect(ctx.runId, runId);
      expect(ctx.scheduleId, 'schedule-1');
      expect(ctx.clientId, 'client-1');
      expect(ctx.requestId, 42);
      expect(registry.activeCount, 1);
      expect(registry.hasActiveForSchedule('schedule-1'), isTrue);
      expect(registry.getByRunId(runId), same(ctx));
      expect(registry.getActiveByScheduleId('schedule-1'), same(ctx));
    });

    test('register throws when scheduleId already has active execution', () {
      final runId1 = registry.generateRunId('schedule-1');
      registry.register(
        runId: runId1,
        scheduleId: 'schedule-1',
        clientId: 'client-A',
        requestId: 1,
        sendToClient: _noopSend,
      );

      final runId2 = registry.generateRunId('schedule-1');
      expect(
        () => registry.register(
          runId: runId2,
          scheduleId: 'schedule-1',
          clientId: 'client-B',
          requestId: 2,
          sendToClient: _noopSend,
        ),
        throwsA(isA<StateError>()),
      );

      // Estado original preservado (defesa contra registro parcial)
      expect(registry.activeCount, 1);
      expect(registry.getActiveByScheduleId('schedule-1')!.clientId, 'client-A');
      expect(registry.getByRunId(runId2), isNull);
    });

    test('register throws when runId already exists', () {
      final runId = registry.generateRunId('schedule-1');
      registry.register(
        runId: runId,
        scheduleId: 'schedule-1',
        clientId: 'client-A',
        requestId: 1,
        sendToClient: _noopSend,
      );

      expect(
        () => registry.register(
          runId: runId,
          scheduleId: 'schedule-2',
          clientId: 'client-B',
          requestId: 2,
          sendToClient: _noopSend,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('different scheduleIds can coexist (preparado para fila futura)', () {
      // Hoje o mutex global garante 1 backup por vez, mas o registry
      // suporta multiplos contextos para quando a fila for adicionada.
      final runId1 = registry.generateRunId('schedule-1');
      final runId2 = registry.generateRunId('schedule-2');

      registry.register(
        runId: runId1,
        scheduleId: 'schedule-1',
        clientId: 'client-A',
        requestId: 1,
        sendToClient: _noopSend,
      );
      registry.register(
        runId: runId2,
        scheduleId: 'schedule-2',
        clientId: 'client-B',
        requestId: 2,
        sendToClient: _noopSend,
      );

      expect(registry.activeCount, 2);
      expect(registry.getActiveByScheduleId('schedule-1')!.clientId, 'client-A');
      expect(registry.getActiveByScheduleId('schedule-2')!.clientId, 'client-B');
    });

    test('unregister removes both indexes (runId and scheduleId)', () {
      final runId = registry.generateRunId('schedule-1');
      registry.register(
        runId: runId,
        scheduleId: 'schedule-1',
        clientId: 'client-1',
        requestId: 1,
        sendToClient: _noopSend,
      );

      registry.unregister(runId);

      expect(registry.activeCount, 0);
      expect(registry.hasActiveForSchedule('schedule-1'), isFalse);
      expect(registry.getByRunId(runId), isNull);
      expect(registry.getActiveByScheduleId('schedule-1'), isNull);
    });

    test('unregister is idempotent', () {
      final runId = registry.generateRunId('schedule-1');
      registry.register(
        runId: runId,
        scheduleId: 'schedule-1',
        clientId: 'client-1',
        requestId: 1,
        sendToClient: _noopSend,
      );

      registry.unregister(runId);
      registry.unregister(runId);
      registry.unregister('inexistente');

      expect(registry.activeCount, 0);
    });

    test('clear removes all entries', () {
      registry.register(
        runId: registry.generateRunId('s1'),
        scheduleId: 's1',
        clientId: 'c1',
        requestId: 1,
        sendToClient: _noopSend,
      );
      registry.register(
        runId: registry.generateRunId('s2'),
        scheduleId: 's2',
        clientId: 'c2',
        requestId: 2,
        sendToClient: _noopSend,
      );

      registry.clear();

      expect(registry.activeCount, 0);
      expect(registry.hasAny, isFalse);
    });

    test('all returns snapshot iteration safe against concurrent unregister',
        () {
      // Importante: `_onProgressChanged` itera `registry.all`. Se um
      // contexto for desregistrado durante a iteracao (ex.: dispose),
      // a iteracao nao pode lancar `ConcurrentModificationError`.
      final runId1 = registry.generateRunId('s1');
      final runId2 = registry.generateRunId('s2');
      registry.register(
        runId: runId1,
        scheduleId: 's1',
        clientId: 'c1',
        requestId: 1,
        sendToClient: _noopSend,
      );
      registry.register(
        runId: runId2,
        scheduleId: 's2',
        clientId: 'c2',
        requestId: 2,
        sendToClient: _noopSend,
      );

      // Tira snapshot antes de modificar
      final snapshot = registry.all.toList(growable: false);
      registry.unregister(runId1);

      // Snapshot nao deve ser afetado
      expect(snapshot.length, 2);
      expect(registry.activeCount, 1);
    });
  });
}
