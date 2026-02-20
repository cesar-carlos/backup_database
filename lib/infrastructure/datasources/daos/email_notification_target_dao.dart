import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/email_notification_targets_table.dart';
import 'package:drift/drift.dart';

part 'email_notification_target_dao.g.dart';

@DriftAccessor(tables: [EmailNotificationTargetsTable])
class EmailNotificationTargetDao extends DatabaseAccessor<AppDatabase>
    with _$EmailNotificationTargetDaoMixin {
  EmailNotificationTargetDao(super.db);

  Future<List<EmailNotificationTargetsTableData>> getAll() =>
      select(emailNotificationTargetsTable).get();

  Future<List<EmailNotificationTargetsTableData>> getByConfigId(
    String configId,
  ) {
    return (select(
      emailNotificationTargetsTable,
    )..where((t) => t.emailConfigId.equals(configId))).get();
  }

  Future<EmailNotificationTargetsTableData?> getById(String id) {
    return (select(
      emailNotificationTargetsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertTarget(EmailNotificationTargetsTableCompanion target) {
    return into(emailNotificationTargetsTable).insert(
      target,
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<bool> updateTarget(
    EmailNotificationTargetsTableCompanion target,
  ) async {
    if (!target.id.present) {
      return false;
    }

    final updated = await (update(
      emailNotificationTargetsTable,
    )..where((t) => t.id.equals(target.id.value))).write(target);
    return updated > 0;
  }

  Future<int> deleteById(String id) {
    return (delete(
      emailNotificationTargetsTable,
    )..where((t) => t.id.equals(id))).go();
  }

  Future<int> deleteByConfigId(String configId) {
    return (delete(
      emailNotificationTargetsTable,
    )..where((t) => t.emailConfigId.equals(configId))).go();
  }
}
