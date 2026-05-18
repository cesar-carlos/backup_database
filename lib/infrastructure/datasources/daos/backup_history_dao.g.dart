// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_history_dao.dart';

// ignore_for_file: type=lint
mixin _$BackupHistoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $BackupHistoryTableTable get backupHistoryTable =>
      attachedDatabase.backupHistoryTable;
  BackupHistoryDaoManager get managers => BackupHistoryDaoManager(this);
}

class BackupHistoryDaoManager {
  final _$BackupHistoryDaoMixin _db;
  BackupHistoryDaoManager(this._db);
  $$BackupHistoryTableTableTableManager get backupHistoryTable =>
      $$BackupHistoryTableTableTableManager(
        _db.attachedDatabase,
        _db.backupHistoryTable,
      );
}
