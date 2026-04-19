import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/execution_queue_items_table.dart';
import 'package:backup_database/infrastructure/socket/server/queued_execution_item.dart';
import 'package:drift/drift.dart';

part 'execution_queue_dao.g.dart';

@DriftAccessor(tables: [ExecutionQueueItemsTable])
class ExecutionQueueDao extends DatabaseAccessor<AppDatabase>
    with _$ExecutionQueueDaoMixin {
  ExecutionQueueDao(super.db);

  Future<int> countRows() async {
    final q = selectOnly(executionQueueItemsTable)
      ..addColumns([executionQueueItemsTable.id.count()]);
    final row = await q.getSingle();
    return row.read(executionQueueItemsTable.id.count()) ?? 0;
  }

  Future<List<QueuedExecutionItem>> loadOrderedFifo() async {
    final rows = await (select(executionQueueItemsTable)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    return rows.map(_rowToItem).toList();
  }

  /// Remove a linha mais antiga (menor `id`). Retorna o item ou null se vazia.
  Future<QueuedExecutionItem?> deleteFifoHead() {
    return transaction(() async {
      final row = await (select(executionQueueItemsTable)
            ..orderBy([(t) => OrderingTerm.asc(t.id)])
            ..limit(1))
          .getSingleOrNull();
      if (row == null) return null;
      await (delete(executionQueueItemsTable)
            ..where((t) => t.id.equals(row.id)))
          .go();
      return _rowToItem(row);
    });
  }

  Future<int> deleteByRunId(String runId) {
    return (delete(executionQueueItemsTable)
          ..where((t) => t.runId.equals(runId)))
        .go();
  }

  Future<void> deleteAll() {
    return delete(executionQueueItemsTable).go();
  }

  Future<bool> tryInsert({
    required QueuedExecutionItem item,
    required int maxQueueSize,
  }) async {
    return transaction(() async {
      final n = await countRows();
      if (n >= maxQueueSize) return false;

      final dup = await (select(executionQueueItemsTable)
            ..where((t) => t.scheduleId.equals(item.scheduleId)))
          .getSingleOrNull();
      if (dup != null) return false;

      await into(executionQueueItemsTable).insert(
        ExecutionQueueItemsTableCompanion.insert(
          runId: item.runId,
          scheduleId: item.scheduleId,
          clientId: item.clientId,
          requestId: item.requestId,
          requestedBy: item.requestedBy,
          queuedAtMicros: item.queuedAt.microsecondsSinceEpoch,
        ),
      );
      return true;
    });
  }

  QueuedExecutionItem _rowToItem(ExecutionQueueItemsTableData row) {
    return QueuedExecutionItem(
      runId: row.runId,
      scheduleId: row.scheduleId,
      clientId: row.clientId,
      requestId: row.requestId,
      requestedBy: row.requestedBy,
      queuedAt: DateTime.fromMicrosecondsSinceEpoch(row.queuedAtMicros),
    );
  }
}
