import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/queue_events.dart';
import 'package:backup_database/infrastructure/socket/server/queue_event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('QueueEventBus', () {
    late List<({String clientId, Message message})> sent;
    late QueueEventBus bus;

    setUp(() {
      sent = [];
      bus = QueueEventBus(
        broadcast: (clientId, message) async {
          sent.add((clientId: clientId, message: message));
        },
        clock: () => DateTime.utc(2026, 4, 19, 12),
      );
    });

    test('publishQueued incrementa sequence e gera eventId UUID', () async {
      await bus.publishQueued(
        clientId: 'c1',
        runId: 'r1',
        scheduleId: 's1',
        queuePosition: 1,
      );
      expect(sent, hasLength(1));
      final ev = readQueueEvent(sent.single.message)!;
      expect(ev.isQueued, isTrue);
      expect(ev.sequence, 1);
      expect(ev.eventId, isNotEmpty);
      expect(Uuid.isValidUUID(fromString: ev.eventId), isTrue);
      expect(bus.currentSequence, 1);
    });

    test('sequence eh monotonico em multiplas publicacoes', () async {
      await bus.publishQueued(
        clientId: 'c1', runId: 'r1', scheduleId: 's1',
      );
      await bus.publishStarted(
        clientId: 'c1', runId: 'r1', scheduleId: 's1',
      );
      await bus.publishDequeued(
        clientId: 'c1', runId: 'r1', scheduleId: 's1', reason: 'cancelled',
      );

      final sequences = sent
          .map((s) => readQueueEvent(s.message)!.sequence)
          .toList();
      expect(sequences, [1, 2, 3]);
    });

    test('eventId e unico por publicacao', () async {
      await bus.publishQueued(clientId: 'c', runId: 'r', scheduleId: 's');
      await bus.publishQueued(clientId: 'c', runId: 'r2', scheduleId: 's2');
      final ids = sent.map((s) => readQueueEvent(s.message)!.eventId).toSet();
      expect(ids, hasLength(2));
    });

    test('initialSequence permite restart com numeracao continua', () async {
      // Apos restart, servidor pode persistir ultimo sequence e
      // continuar a partir dele em vez de zerar.
      bus = QueueEventBus(
        broadcast: (c, m) async => sent.add((clientId: c, message: m)),
        initialSequence: 100,
      );
      await bus.publishQueued(clientId: 'c', runId: 'r', scheduleId: 's');
      final ev = readQueueEvent(sent.single.message)!;
      expect(ev.sequence, 101);
    });

    test('falha de broadcast nao derruba o bus (log e continua)', () async {
      bus = QueueEventBus(
        broadcast: (c, m) async => throw StateError('client gone'),
      );
      // Nao deve jogar — eventos sao fire-and-forget do ponto de
      // vista do publisher. Falha no broadcast e log apenas.
      await expectLater(
        bus.publishQueued(clientId: 'c', runId: 'r', scheduleId: 's'),
        completes,
      );
      // sequence ainda incrementou (evento foi gerado mesmo se nao
      // entregou ao cliente)
      expect(bus.currentSequence, 1);
    });

    test('publishDequeued inclui reason no payload', () async {
      await bus.publishDequeued(
        clientId: 'c', runId: 'r', scheduleId: 's', reason: 'dispatched',
      );
      final ev = readQueueEvent(sent.single.message)!;
      expect(ev.reason, 'dispatched');
    });

    test('publishQueued inclui queuePosition e requestedBy', () async {
      await bus.publishQueued(
        clientId: 'c1',
        runId: 'r',
        scheduleId: 's',
        queuePosition: 3,
        requestedBy: 'c1',
      );
      final ev = readQueueEvent(sent.single.message)!;
      expect(ev.queuePosition, 3);
      expect(ev.requestedBy, 'c1');
    });
  });
}
