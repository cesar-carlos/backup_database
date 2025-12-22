import 'package:drift/drift.dart';

import '../local/database.dart';
import '../local/tables/postgres_configs_table.dart';

part 'postgres_config_dao.g.dart';

@DriftAccessor(tables: [PostgresConfigsTable])
class PostgresConfigDao extends DatabaseAccessor<AppDatabase>
    with _$PostgresConfigDaoMixin {
  PostgresConfigDao(super.db);

  Future<List<PostgresConfigsTableData>> getAll() =>
      select(postgresConfigsTable).get();

  Future<PostgresConfigsTableData?> getById(String id) =>
      (select(postgresConfigsTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> insertConfig(PostgresConfigsTableCompanion config) =>
      into(postgresConfigsTable).insert(config);

  Future<bool> updateConfig(PostgresConfigsTableCompanion config) =>
      update(postgresConfigsTable).replace(config);

  Future<int> deleteConfig(String id) =>
      (delete(postgresConfigsTable)..where((t) => t.id.equals(id))).go();

  Future<List<PostgresConfigsTableData>> getEnabled() =>
      (select(postgresConfigsTable)..where((t) => t.enabled.equals(true)))
          .get();

  Stream<List<PostgresConfigsTableData>> watchAll() =>
      select(postgresConfigsTable).watch();
}

