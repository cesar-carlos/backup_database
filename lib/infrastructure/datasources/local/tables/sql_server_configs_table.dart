import 'package:drift/drift.dart';

class SqlServerConfigsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get server => text()();
  TextColumn get database => text()();
  TextColumn get username => text()();
  TextColumn get password => text()(); // Criptografado
  IntColumn get port => integer().withDefault(const Constant(1433))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
