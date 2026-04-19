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
}
