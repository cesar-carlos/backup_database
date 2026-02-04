import 'package:drift/drift.dart';

class ConnectionLogsTable extends Table {
  TextColumn get id => text()();
  TextColumn get clientHost => text()();
  TextColumn get serverId => text().nullable()();
  BoolColumn get success => boolean()();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get clientId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
