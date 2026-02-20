import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/email_configs_table.dart';
import 'package:drift/drift.dart';

part 'email_config_dao.g.dart';

@DriftAccessor(tables: [EmailConfigsTable])
class EmailConfigDao extends DatabaseAccessor<AppDatabase>
    with _$EmailConfigDaoMixin {
  EmailConfigDao(super.db);

  Future<List<EmailConfigsTableData>> getAll() =>
      select(emailConfigsTable).get();

  Future<EmailConfigsTableData?> getById(String id) => (select(
    emailConfigsTable,
  )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<EmailConfigsTableData?> get() =>
      select(emailConfigsTable).getSingleOrNull();

  Future<int> insertConfig(EmailConfigsTableCompanion config) =>
      into(emailConfigsTable).insert(config);

  Future<bool> updateConfig(EmailConfigsTableCompanion config) async {
    if (!config.id.present) {
      return false;
    }

    final existing = await getById(config.id.value);
    if (existing == null) {
      return false;
    }

    final updated = await (update(
      emailConfigsTable,
    )..where((tbl) => tbl.id.equals(config.id.value))).write(config);
    return updated > 0;
  }

  Future<int> deleteById(String id) =>
      (delete(emailConfigsTable)..where((tbl) => tbl.id.equals(id))).go();

  Future<int> deleteAll() => delete(emailConfigsTable).go();

  Stream<EmailConfigsTableData?> watch() =>
      select(emailConfigsTable).watchSingleOrNull();
}
