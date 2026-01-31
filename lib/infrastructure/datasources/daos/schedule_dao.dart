import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/schedules_table.dart';
import 'package:drift/drift.dart';

part 'schedule_dao.g.dart';

@DriftAccessor(tables: [SchedulesTable])
class ScheduleDao extends DatabaseAccessor<AppDatabase>
    with _$ScheduleDaoMixin {
  ScheduleDao(super.db);

  Future<List<SchedulesTableData>> getAll() => select(schedulesTable).get();

  Future<SchedulesTableData?> getById(String id) =>
      (select(schedulesTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertSchedule(SchedulesTableCompanion schedule) =>
      into(schedulesTable).insert(schedule);

  Future<bool> updateSchedule(SchedulesTableCompanion schedule) =>
      update(schedulesTable).replace(schedule);

  Future<int> deleteSchedule(String id) =>
      (delete(schedulesTable)..where((t) => t.id.equals(id))).go();

  Future<List<SchedulesTableData>> getEnabled() =>
      (select(schedulesTable)..where((t) => t.enabled.equals(true))).get();

  Future<List<SchedulesTableData>> getByDatabaseConfig(
    String databaseConfigId,
  ) => (select(
    schedulesTable,
  )..where((t) => t.databaseConfigId.equals(databaseConfigId))).get();

  Future<int> updateLastRun(
    String id,
    DateTime lastRunAt,
    DateTime? nextRunAt,
  ) {
    return (update(schedulesTable)..where((t) => t.id.equals(id))).write(
      SchedulesTableCompanion(
        lastRunAt: Value(lastRunAt),
        nextRunAt: Value(nextRunAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Stream<List<SchedulesTableData>> watchAll() => select(schedulesTable).watch();
}
