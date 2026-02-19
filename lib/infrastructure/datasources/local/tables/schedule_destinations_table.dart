import 'package:backup_database/infrastructure/datasources/local/tables/backup_destinations_table.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/schedules_table.dart';
import 'package:drift/drift.dart';

class ScheduleDestinationsTable extends Table {
  TextColumn get id => text()();
  TextColumn get scheduleId => text().references(
    SchedulesTable,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get destinationId => text().references(
    BackupDestinationsTable,
    #id,
    onDelete: KeyAction.restrict,
  )();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {scheduleId, destinationId},
  ];
}
