// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_log_dao.dart';

// ignore_for_file: type=lint
mixin _$BackupLogDaoMixin on DatabaseAccessor<AppDatabase> {
  $BackupLogsTableTable get backupLogsTable => attachedDatabase.backupLogsTable;
  BackupLogDaoManager get managers => BackupLogDaoManager(this);
}

class BackupLogDaoManager {
  final _$BackupLogDaoMixin _db;
  BackupLogDaoManager(this._db);
  $$BackupLogsTableTableTableManager get backupLogsTable =>
      $$BackupLogsTableTableTableManager(
        _db.attachedDatabase,
        _db.backupLogsTable,
      );
}
