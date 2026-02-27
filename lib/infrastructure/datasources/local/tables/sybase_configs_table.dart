import 'package:drift/drift.dart';

class SybaseConfigsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get serverName => text()(); // Nome da máquina/servidor
  TextColumn get databaseName => text()(); // Nome do banco de dados (DBN)
  TextColumn get databaseFile => text()();
  IntColumn get port => integer().withDefault(const Constant(2638))();
  TextColumn get username => text()();
  TextColumn get password => text()(); // Criptografado
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get isReplicationEnvironment =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
