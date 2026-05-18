// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_destination_dao.dart';

// ignore_for_file: type=lint
mixin _$ScheduleDestinationDaoMixin on DatabaseAccessor<AppDatabase> {
  $SchedulesTableTable get schedulesTable => attachedDatabase.schedulesTable;
  $BackupDestinationsTableTable get backupDestinationsTable =>
      attachedDatabase.backupDestinationsTable;
  $ScheduleDestinationsTableTable get scheduleDestinationsTable =>
      attachedDatabase.scheduleDestinationsTable;
  ScheduleDestinationDaoManager get managers =>
      ScheduleDestinationDaoManager(this);
}

class ScheduleDestinationDaoManager {
  final _$ScheduleDestinationDaoMixin _db;
  ScheduleDestinationDaoManager(this._db);
  $$SchedulesTableTableTableManager get schedulesTable =>
      $$SchedulesTableTableTableManager(
        _db.attachedDatabase,
        _db.schedulesTable,
      );
  $$BackupDestinationsTableTableTableManager get backupDestinationsTable =>
      $$BackupDestinationsTableTableTableManager(
        _db.attachedDatabase,
        _db.backupDestinationsTable,
      );
  $$ScheduleDestinationsTableTableTableManager get scheduleDestinationsTable =>
      $$ScheduleDestinationsTableTableTableManager(
        _db.attachedDatabase,
        _db.scheduleDestinationsTable,
      );
}
