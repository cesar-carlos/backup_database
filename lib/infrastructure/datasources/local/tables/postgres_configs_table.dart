import 'package:drift/drift.dart';

class PostgresConfigsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get host => text()();
  TextColumn get database => text()();
  TextColumn get username => text()();
  TextColumn get password => text()(); // Criptografado
  IntColumn get port => integer().withDefault(const Constant(5432))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
