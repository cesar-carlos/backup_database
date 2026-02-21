import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/email_test_audit_table.dart';
import 'package:drift/drift.dart';

part 'email_test_audit_dao.g.dart';

@DriftAccessor(tables: [EmailTestAuditTable])
class EmailTestAuditDao extends DatabaseAccessor<AppDatabase>
    with _$EmailTestAuditDaoMixin {
  EmailTestAuditDao(super.db);

  Future<int> insertAudit(EmailTestAuditTableCompanion companion) {
    return into(emailTestAuditTable).insert(companion);
  }

  Future<List<EmailTestAuditTableData>> getRecent({
    String? configId,
    DateTime? startAt,
    DateTime? endAt,
    int limit = 100,
  }) {
    final query = select(emailTestAuditTable)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);

    if (configId != null && configId.trim().isNotEmpty) {
      query.where((t) => t.configId.equals(configId));
    }
    if (startAt != null) {
      query.where((t) => t.createdAt.isBiggerOrEqualValue(startAt));
    }
    if (endAt != null) {
      query.where((t) => t.createdAt.isSmallerOrEqualValue(endAt));
    }

    return query.get();
  }
}
