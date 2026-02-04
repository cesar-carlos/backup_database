import 'package:drift/drift.dart';

class ServerCredentialsTable extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text()();
  TextColumn get passwordHash => text()();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
  TextColumn get description => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
