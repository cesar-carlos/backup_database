import 'package:drift/drift.dart';

class BackupLogsTable extends Table {
  TextColumn get id => text()();
  TextColumn get backupHistoryId => text().nullable()();
  TextColumn get level => text()(); // 'debug', 'info', 'warning', 'error'
  TextColumn get category => text()(); // 'execution', 'system', 'audit'
  TextColumn get message => text()();
  TextColumn get details => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
