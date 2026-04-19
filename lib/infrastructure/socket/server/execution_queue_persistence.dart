import 'package:backup_database/infrastructure/datasources/daos/execution_queue_dao.dart';
import 'package:backup_database/infrastructure/socket/server/queued_execution_item.dart';

/// Backend de persistencia para o servico de fila de execucao (F2.16).
abstract class ExecutionQueuePersistence {
  Future<List<QueuedExecutionItem>> loadOrderedFifo();

  /// Remove entradas excedentes (mais antigas primeiro) ate no maximo [maxKeep].
  Future<void> trimToMaxSize(int maxKeep);

  Future<bool> tryInsert({
    required QueuedExecutionItem item,
    required int maxQueueSize,
  });

  Future<QueuedExecutionItem?> deleteFifoHead();

  Future<int> deleteByRunId(String runId);

  Future<void> deleteAll();
}

/// Implementacao Drift ([ExecutionQueueDao]).
class DriftExecutionQueuePersistence implements ExecutionQueuePersistence {
  DriftExecutionQueuePersistence(this._dao);

  final ExecutionQueueDao _dao;

  @override
  Future<List<QueuedExecutionItem>> loadOrderedFifo() =>
      _dao.loadOrderedFifo();

  @override
  Future<void> trimToMaxSize(int maxKeep) async {
    while (await _dao.countRows() > maxKeep) {
      await _dao.deleteFifoHead();
    }
  }

  @override
  Future<bool> tryInsert({
    required QueuedExecutionItem item,
    required int maxQueueSize,
  }) =>
      _dao.tryInsert(item: item, maxQueueSize: maxQueueSize);

  @override
  Future<QueuedExecutionItem?> deleteFifoHead() => _dao.deleteFifoHead();

  @override
  Future<int> deleteByRunId(String runId) => _dao.deleteByRunId(runId);

  @override
  Future<void> deleteAll() => _dao.deleteAll();
}
