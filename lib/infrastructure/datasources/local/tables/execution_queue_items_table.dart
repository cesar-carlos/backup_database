import 'package:drift/drift.dart';

/// Fila persistente de execucoes remotas (F2.16). Ordem FIFO = `id`
/// autoincrement; `schedule_id` UNIQUE evita duplicar o mesmo agendamento.
class ExecutionQueueItemsTable extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get runId => text().unique()();

  TextColumn get scheduleId => text().unique()();

  TextColumn get clientId => text()();

  IntColumn get requestId => integer()();

  TextColumn get requestedBy => text()();

  IntColumn get queuedAtMicros => integer()();

  /// PR-6: TTL (microseconds since epoch). Itens nao drenados ate este
  /// instante sao removidos pelo `pruneExpired` da `ExecutionQueueService`
  /// e publicados como `backupDequeued(reason='ttlExpired')`. Nullable
  /// para preservar compat com itens persistidos pre-v34 (sem TTL).
  IntColumn get expiresAtMicros => integer().nullable()();
}
