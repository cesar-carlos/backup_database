import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/backup_logs_table.dart';
import 'package:drift/drift.dart';

part 'backup_log_dao.g.dart';

@DriftAccessor(tables: [BackupLogsTable])
class BackupLogDao extends DatabaseAccessor<AppDatabase>
    with _$BackupLogDaoMixin {
  BackupLogDao(super.db);

  Future<List<BackupLogsTableData>> getFiltered({
    int? limit,
    int? offset,
    String? level,
    String? category,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) {
    final query = select(backupLogsTable);
    if (level != null) query.where((t) => t.level.equals(level));
    if (category != null) query.where((t) => t.category.equals(category));
    if (startDate != null) {
      query.where((t) => t.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.createdAt.isSmallerOrEqualValue(endDate));
    }
    final search = searchQuery?.trim().toLowerCase() ?? '';
    if (search.isNotEmpty) {
      Expression<bool> containsLiteral(Expression<String> column) =>
          FunctionCallExpression<int>('instr', [
            column.lower(),
            Variable(search),
          ]).isBiggerThanValue(0);
      query.where(
        (t) =>
            containsLiteral(t.message) |
            containsLiteral(t.details) |
            containsLiteral(t.backupHistoryId),
      );
    }
    query.orderBy([
      (t) => OrderingTerm.desc(t.createdAt),
      (t) => OrderingTerm.asc(t.id),
    ]);
    if (limit != null || offset != null) {
      query.limit(limit ?? -1, offset: offset);
    }
    return query.get();
  }

  Future<List<BackupLogsTableData>> getAll({int? limit, int? offset}) {
    final query = select(backupLogsTable)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (limit != null) query.limit(limit, offset: offset);
    return query.get();
  }

  Future<int> insertLog(BackupLogsTableCompanion log) =>
      into(backupLogsTable).insert(log);

  Future<int> insertOrReplaceLog(BackupLogsTableCompanion log) =>
      into(backupLogsTable).insert(
        log,
        mode: InsertMode.insertOrReplace,
      );

  Future<List<BackupLogsTableData>> getByBackupHistory(
    String backupHistoryId,
  ) => (select(
    backupLogsTable,
  )..where((t) => t.backupHistoryId.equals(backupHistoryId))).get();

  Future<List<BackupLogsTableData>> getByLevel(String level) =>
      (select(backupLogsTable)..where((t) => t.level.equals(level))).get();

  Future<List<BackupLogsTableData>> getByCategory(String category) => (select(
    backupLogsTable,
  )..where((t) => t.category.equals(category))).get();

  Future<List<BackupLogsTableData>> getByDateRange(
    DateTime start,
    DateTime end,
  ) {
    return (select(backupLogsTable)
          ..where((t) => t.createdAt.isBetweenValues(start, end))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<List<BackupLogsTableData>> search(String query) => (select(
    backupLogsTable,
  )..where((t) => t.message.contains(query) | t.details.contains(query))).get();

  Future<int> deleteOlderThan(DateTime date) => (delete(
    backupLogsTable,
  )..where((t) => t.createdAt.isSmallerThanValue(date))).go();

  Stream<List<BackupLogsTableData>> watchAll() =>
      select(backupLogsTable).watch();
}
