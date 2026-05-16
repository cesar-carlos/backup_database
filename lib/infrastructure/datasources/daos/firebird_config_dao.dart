import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/firebird_configs_table.dart';
import 'package:drift/drift.dart';

part 'firebird_config_dao.g.dart';

@DriftAccessor(tables: [FirebirdConfigsTable])
class FirebirdConfigDao extends DatabaseAccessor<AppDatabase>
    with _$FirebirdConfigDaoMixin {
  FirebirdConfigDao(super.db);

  Future<List<FirebirdConfigsTableData>> getAll() =>
      select(firebirdConfigsTable).get();

  Future<FirebirdConfigsTableData?> getById(String id) => (select(
    firebirdConfigsTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertConfig(FirebirdConfigsTableCompanion config) =>
      into(firebirdConfigsTable).insert(config);

  Future<bool> updateConfig(FirebirdConfigsTableCompanion config) =>
      update(firebirdConfigsTable).replace(config);

  Future<int> deleteConfig(String id) =>
      (delete(firebirdConfigsTable)..where((t) => t.id.equals(id))).go();

  Future<List<FirebirdConfigsTableData>> getEnabled() => (select(
    firebirdConfigsTable,
  )..where((t) => t.enabled.equals(true))).get();
}
