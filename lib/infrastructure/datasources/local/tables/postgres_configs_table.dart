import 'package:drift/drift.dart';

class PostgresConfigsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get host => text()();
  TextColumn get database => text()();
  TextColumn get username => text()();
  // Coluna mantida por compatibilidade de schema; valor é sempre `''`
  // porque a senha real fica em secure storage (`SecureCredentialKeys
  // .postgresPasswordKey`). Remover via migration drift quando houver
  // janela para aplicar `M00xx_drop_postgres_password_column`.
  TextColumn get password => text()();
  IntColumn get port => integer().withDefault(const Constant(5432))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
