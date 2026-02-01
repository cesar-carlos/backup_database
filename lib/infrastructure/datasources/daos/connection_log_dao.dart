import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/connection_logs_table.dart';
import 'package:drift/drift.dart';

part 'connection_log_dao.g.dart';

@DriftAccessor(tables: [ConnectionLogsTable])
class ConnectionLogDao extends DatabaseAccessor<AppDatabase>
    with _$ConnectionLogDaoMixin {
  ConnectionLogDao(super.db);

  Future<List<ConnectionLogsTableData>> getAll() =>
      select(connectionLogsTable).get();

  Future<ConnectionLogsTableData?> getById(String id) =>
      (select(connectionLogsTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> insertLog(ConnectionLogsTableCompanion log) =>
      into(connectionLogsTable).insert(log);

  Future<int> deleteLog(String id) =>
      (delete(connectionLogsTable)..where((t) => t.id.equals(id))).go();

  Future<List<ConnectionLogsTableData>> getSuccessfulConnections() =>
      (select(connectionLogsTable)..where((t) => t.success.equals(true))).get();

  Future<List<ConnectionLogsTableData>> getFailedConnections() =>
      (select(connectionLogsTable)..where((t) => t.success.equals(false))).get();

  Future<List<ConnectionLogsTableData>> getRecentLogs(int limit) =>
      (select(connectionLogsTable)
        ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
        ..limit(limit)).get();

  Future<int> deleteOldLogs(DateTime beforeDate) =>
      (delete(connectionLogsTable)..where((t) => t.timestamp.isSmallerThanValue(beforeDate))).go();

  Stream<List<ConnectionLogsTableData>> watchAll() =>
      select(connectionLogsTable).watch();
}
