// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_dao.dart';

// ignore_for_file: type=lint
mixin _$ScheduleDaoMixin on DatabaseAccessor<AppDatabase> {
  $SchedulesTableTable get schedulesTable => attachedDatabase.schedulesTable;
  ScheduleDaoManager get managers => ScheduleDaoManager(this);
}

class ScheduleDaoManager {
  final _$ScheduleDaoMixin _db;
  ScheduleDaoManager(this._db);
  $$SchedulesTableTableTableManager get schedulesTable =>
      $$SchedulesTableTableTableManager(
        _db.attachedDatabase,
        _db.schedulesTable,
      );
}
