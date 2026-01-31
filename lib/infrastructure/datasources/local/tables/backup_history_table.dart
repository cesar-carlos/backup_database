import 'package:drift/drift.dart';

class BackupHistoryTable extends Table {
  TextColumn get id => text()();
  TextColumn get scheduleId => text().nullable()();
  TextColumn get databaseName => text()();
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

  @override
  Set<Column> get primaryKey => {id};
}
