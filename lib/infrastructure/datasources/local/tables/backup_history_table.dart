import 'package:drift/drift.dart';

class BackupHistoryTable extends Table {
  TextColumn get id => text()();

  /// Correlacao com `runId` de execucao remota (PR-3c / `getExecutionStatus`).
  TextColumn get runId => text().nullable()();
  TextColumn get scheduleId => text().nullable()();
  TextColumn get databaseName => text()();

  /// PR-6: timestamp do ultimo `backupProgress` registrado para esta
  /// execucao. Usado pelo watchdog runtime no `SchedulerService` para
  /// detectar orchestrator travado (sem progresso por
  /// `runningHeartbeatTimeout`). Nullable para preservar compat com
  /// linhas anteriores a v34.
  DateTimeColumn get lastProgressAt => dateTime().nullable()();
  TextColumn get databaseType => text()();
  TextColumn get backupPath => text()();
  IntColumn get fileSize => integer()();
  TextColumn get backupType => text().withDefault(
    const Constant('full'),
  )(); // 'full', 'differential', 'log'
  TextColumn get status => text()(); // 'success', 'error', 'warning', 'running'
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
  TextColumn get metrics => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
