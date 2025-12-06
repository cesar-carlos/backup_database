import 'package:drift/drift.dart';

class SchedulesTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get databaseConfigId => text()();
  TextColumn get databaseType => text()(); // 'sqlServer' ou 'sybase'
  TextColumn get scheduleType =>
      text()(); // 'daily', 'weekly', 'monthly', 'interval'
  TextColumn get scheduleConfig => text()(); // JSON
  TextColumn get destinationIds => text()(); // JSON array
  TextColumn get backupFolder => text().withDefault(const Constant(''))();
  BoolColumn get compressBackup =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastRunAt => dateTime().nullable()();
  DateTimeColumn get nextRunAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

