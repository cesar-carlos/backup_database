import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_persistence.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriftExecutionQueuePersistence + ExecutionQueueService', () {
    test('initialize reidrata fila apos novo servico com mesma base', () async {
      final db = AppDatabase.inMemory();
      addTearDown(() async {
        await db.close();
      });

      final p1 = DriftExecutionQueuePersistence(db.executionQueueDao);
      final q1 = ExecutionQueueService(persistence: p1);
      await q1.initialize();

      final item = await q1.tryEnqueue(
        scheduleId: 'sch-1',
        clientId: 'c1',
        requestId: 7,
        requestedBy: 'c1',
      );
      expect(item, isNotNull);
      expect(q1.queueSize, 1);

      final p2 = DriftExecutionQueuePersistence(db.executionQueueDao);
      final q2 = ExecutionQueueService(persistence: p2);
      await q2.initialize();

      expect(q2.queueSize, 1);
      expect(q2.snapshot().single.runId, item!.runId);
    });

    test('trimToMaxSize remove entradas mais antigas', () async {
      final db = AppDatabase.inMemory();
      addTearDown(() async {
        await db.close();
      });

      final dao = db.executionQueueDao;
      final p = DriftExecutionQueuePersistence(dao);

      Future<void> insert(String scheduleId, String runId) async {
        await dao.tryInsert(
          item: QueuedExecutionItem(
            runId: runId,
            scheduleId: scheduleId,
            clientId: 'c',
            requestId: 1,
            requestedBy: 'c',
            queuedAt: DateTime.utc(2026),
          ),
          maxQueueSize: 10,
        );
      }

      await insert('a', 'a_r1');
      await insert('b', 'b_r1');
      await insert('c', 'c_r1');

      await p.trimToMaxSize(1);
      final rows = await dao.loadOrderedFifo();
      expect(rows, hasLength(1));
      expect(rows.single.scheduleId, 'c');
    });
  });
}
