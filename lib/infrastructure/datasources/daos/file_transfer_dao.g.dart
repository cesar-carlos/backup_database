// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_transfer_dao.dart';

// ignore_for_file: type=lint
mixin _$FileTransferDaoMixin on DatabaseAccessor<AppDatabase> {
  $FileTransfersTableTable get fileTransfersTable =>
      attachedDatabase.fileTransfersTable;
  FileTransferDaoManager get managers => FileTransferDaoManager(this);
}

class FileTransferDaoManager {
  final _$FileTransferDaoMixin _db;
  FileTransferDaoManager(this._db);
  $$FileTransfersTableTableTableManager get fileTransfersTable =>
      $$FileTransfersTableTableTableManager(
        _db.attachedDatabase,
        _db.fileTransfersTable,
      );
}
