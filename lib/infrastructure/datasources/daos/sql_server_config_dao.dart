import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/sql_server_configs_table.dart';
import 'package:drift/drift.dart';

part 'sql_server_config_dao.g.dart';

@DriftAccessor(tables: [SqlServerConfigsTable])
class SqlServerConfigDao extends DatabaseAccessor<AppDatabase>
    with _$SqlServerConfigDaoMixin {
  SqlServerConfigDao(super.db);

  Future<List<SqlServerConfigsTableData>> getAll() =>
      select(sqlServerConfigsTable).get();

  Future<SqlServerConfigsTableData?> getById(String id) => (select(
    sqlServerConfigsTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertConfig(SqlServerConfigsTableCompanion config) =>
      into(sqlServerConfigsTable).insert(config);

  Future<bool> updateConfig(SqlServerConfigsTableCompanion config) =>
      update(sqlServerConfigsTable).replace(config);

  Future<int> deleteConfig(String id) =>
      (delete(sqlServerConfigsTable)..where((t) => t.id.equals(id))).go();

  Future<List<SqlServerConfigsTableData>> getEnabled() => (select(
    sqlServerConfigsTable,
  )..where((t) => t.enabled.equals(true))).get();

  Stream<List<SqlServerConfigsTableData>> watchAll() =>
      select(sqlServerConfigsTable).watch();
}
