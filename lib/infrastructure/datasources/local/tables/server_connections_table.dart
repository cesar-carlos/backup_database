import 'package:drift/drift.dart';

class ServerConnectionsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get serverId => text()();
  TextColumn get host => text()();
  IntColumn get port => integer().withDefault(const Constant(9527))();
  TextColumn get password => text()();
  BoolColumn get isOnline => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastConnectedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
