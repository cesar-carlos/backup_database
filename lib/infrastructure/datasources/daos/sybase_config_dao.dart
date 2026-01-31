import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/sybase_configs_table.dart';
import 'package:drift/drift.dart';

part 'sybase_config_dao.g.dart';

@DriftAccessor(tables: [SybaseConfigsTable])
class SybaseConfigDao extends DatabaseAccessor<AppDatabase>
    with _$SybaseConfigDaoMixin {
  SybaseConfigDao(super.db);

  Future<List<SybaseConfigsTableData>> getAll() =>
      select(sybaseConfigsTable).get();

  Future<SybaseConfigsTableData?> getById(String id) => (select(
    sybaseConfigsTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertConfig(SybaseConfigsTableCompanion config) =>
      into(sybaseConfigsTable).insert(config);

  Future<bool> updateConfig(SybaseConfigsTableCompanion config) =>
      update(sybaseConfigsTable).replace(config);

  Future<int> deleteConfig(String id) =>
      (delete(sybaseConfigsTable)..where((t) => t.id.equals(id))).go();

  Future<List<SybaseConfigsTableData>> getEnabled() =>
      (select(sybaseConfigsTable)..where((t) => t.enabled.equals(true))).get();

  Stream<List<SybaseConfigsTableData>> watchAll() =>
      select(sybaseConfigsTable).watch();
}
