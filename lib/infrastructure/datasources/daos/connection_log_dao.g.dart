// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection_log_dao.dart';

// ignore_for_file: type=lint
mixin _$ConnectionLogDaoMixin on DatabaseAccessor<AppDatabase> {
  $ConnectionLogsTableTable get connectionLogsTable =>
      attachedDatabase.connectionLogsTable;
  ConnectionLogDaoManager get managers => ConnectionLogDaoManager(this);
}

class ConnectionLogDaoManager {
  final _$ConnectionLogDaoMixin _db;
  ConnectionLogDaoManager(this._db);
  $$ConnectionLogsTableTableTableManager get connectionLogsTable =>
      $$ConnectionLogsTableTableTableManager(
        _db.attachedDatabase,
        _db.connectionLogsTable,
      );
}
