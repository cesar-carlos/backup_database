import 'package:drift/drift.dart';

import '../local/database.dart';
import '../local/tables/email_configs_table.dart';

part 'email_config_dao.g.dart';

@DriftAccessor(tables: [EmailConfigsTable])
class EmailConfigDao extends DatabaseAccessor<AppDatabase>
    with _$EmailConfigDaoMixin {
  EmailConfigDao(super.db);

  Future<EmailConfigsTableData?> get() =>
      select(emailConfigsTable).getSingleOrNull();

  Future<int> insertConfig(EmailConfigsTableCompanion config) =>
      into(emailConfigsTable).insert(config);

  Future<bool> updateConfig(EmailConfigsTableCompanion config) async {
    if (!config.id.present) {
      return false;
    }
    
    final existing = await get();
    if (existing == null) {
      return false;
    }
    
    final updated = await (update(emailConfigsTable)..where((tbl) => tbl.id.equals(config.id.value))).write(config);
    return updated > 0;
  }

  Future<int> deleteAll() => delete(emailConfigsTable).go();

  Stream<EmailConfigsTableData?> watch() =>
      select(emailConfigsTable).watchSingleOrNull();
}

