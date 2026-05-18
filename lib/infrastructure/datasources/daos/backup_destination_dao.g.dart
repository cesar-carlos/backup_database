// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_destination_dao.dart';

// ignore_for_file: type=lint
mixin _$BackupDestinationDaoMixin on DatabaseAccessor<AppDatabase> {
  $BackupDestinationsTableTable get backupDestinationsTable =>
      attachedDatabase.backupDestinationsTable;
  BackupDestinationDaoManager get managers => BackupDestinationDaoManager(this);
}

class BackupDestinationDaoManager {
  final _$BackupDestinationDaoMixin _db;
  BackupDestinationDaoManager(this._db);
  $$BackupDestinationsTableTableTableManager get backupDestinationsTable =>
      $$BackupDestinationsTableTableTableManager(
        _db.attachedDatabase,
        _db.backupDestinationsTable,
      );
}
