import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/schedule_destinations_table.dart';
import 'package:drift/drift.dart';

part 'schedule_destination_dao.g.dart';

@DriftAccessor(tables: [ScheduleDestinationsTable])
class ScheduleDestinationDao extends DatabaseAccessor<AppDatabase>
    with _$ScheduleDestinationDaoMixin {
  ScheduleDestinationDao(super.db);

  Future<List<ScheduleDestinationsTableData>> getByScheduleId(
    String scheduleId,
  ) {
    return (select(
      scheduleDestinationsTable,
    )..where((t) => t.scheduleId.equals(scheduleId))).get();
  }

  Future<List<ScheduleDestinationsTableData>> getByDestinationId(
    String destinationId,
  ) {
    return (select(
      scheduleDestinationsTable,
    )..where((t) => t.destinationId.equals(destinationId))).get();
  }

  Future<int> insertRelation(ScheduleDestinationsTableCompanion relation) {
    return into(scheduleDestinationsTable).insert(
      relation,
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<int> deleteByScheduleId(String scheduleId) {
    return (delete(
      scheduleDestinationsTable,
    )..where((t) => t.scheduleId.equals(scheduleId))).go();
  }

  Future<int> deleteByDestinationId(String destinationId) {
    return (delete(
      scheduleDestinationsTable,
    )..where((t) => t.destinationId.equals(destinationId))).go();
  }
}
