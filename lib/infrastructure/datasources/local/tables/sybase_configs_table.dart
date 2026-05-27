import 'package:drift/drift.dart';

class SybaseConfigsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get serverName => text()(); // Nome da máquina/servidor
  TextColumn get databaseName => text()(); // Nome do banco de dados (DBN)
  TextColumn get databaseFile => text()();
  IntColumn get port => integer().withDefault(const Constant(2638))();
  TextColumn get username => text()();
  // Coluna mantida por compatibilidade de schema; valor é sempre `''`
  // porque a senha real fica em secure storage (`SecureCredentialKeys
  // .sybasePasswordKey`). Remover via migration drift quando houver
  // janela para aplicar `M00xx_drop_sybase_password_column`.
  TextColumn get password => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get isReplicationEnvironment =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
