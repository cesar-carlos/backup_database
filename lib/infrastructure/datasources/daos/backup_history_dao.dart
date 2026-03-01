import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/backup_history_table.dart';
import 'package:drift/drift.dart';

part 'backup_history_dao.g.dart';

@DriftAccessor(tables: [BackupHistoryTable])
class BackupHistoryDao extends DatabaseAccessor<AppDatabase>
    with _$BackupHistoryDaoMixin {
  BackupHistoryDao(super.db);

  Future<List<BackupHistoryTableData>> getAll({int? limit, int? offset}) {
    final query = select(backupHistoryTable)
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    if (limit != null) query.limit(limit, offset: offset);
    return query.get();
  }

  Future<BackupHistoryTableData?> getById(String id) => (select(
    backupHistoryTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertHistory(BackupHistoryTableCompanion history) =>
      into(backupHistoryTable).insert(history);

  Future<bool> updateHistory(BackupHistoryTableCompanion history) =>
      update(backupHistoryTable).replace(history);

  Future<int> updateHistoryIfRunning(BackupHistoryTableCompanion history) =>
      (update(backupHistoryTable)..where(
            (t) => t.id.equals(history.id.value) & t.status.equals('running'),
          ))
          .write(history);

  Future<int> deleteHistory(String id) =>
      (delete(backupHistoryTable)..where((t) => t.id.equals(id))).go();

  Future<List<BackupHistoryTableData>> getBySchedule(String scheduleId) =>
      (select(
        backupHistoryTable,
      )..where((t) => t.scheduleId.equals(scheduleId))).get();

  Future<List<BackupHistoryTableData>> getByStatus(String status) =>
      (select(backupHistoryTable)..where((t) => t.status.equals(status))).get();

  Future<List<BackupHistoryTableData>> getByDateRange(
    DateTime start,
    DateTime end,
  ) {
    return (select(backupHistoryTable)
          ..where((t) => t.startedAt.isBetweenValues(start, end))
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
        .get();
  }

  Future<BackupHistoryTableData?> getLastBySchedule(String scheduleId) =>
      (select(backupHistoryTable)
            ..where((t) => t.scheduleId.equals(scheduleId))
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<int> deleteOlderThan(DateTime date) => (delete(
    backupHistoryTable,
  )..where((t) => t.startedAt.isSmallerThanValue(date))).go();

  Stream<List<BackupHistoryTableData>> watchAll() =>
      select(backupHistoryTable).watch();
}
