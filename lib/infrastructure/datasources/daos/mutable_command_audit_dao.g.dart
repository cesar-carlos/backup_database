// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mutable_command_audit_dao.dart';

// ignore_for_file: type=lint
mixin _$MutableCommandAuditDaoMixin on DatabaseAccessor<AppDatabase> {
  $MutableCommandAuditTableTable get mutableCommandAuditTable =>
      attachedDatabase.mutableCommandAuditTable;
  MutableCommandAuditDaoManager get managers =>
      MutableCommandAuditDaoManager(this);
}

class MutableCommandAuditDaoManager {
  final _$MutableCommandAuditDaoMixin _db;
  MutableCommandAuditDaoManager(this._db);
  $$MutableCommandAuditTableTableTableManager get mutableCommandAuditTable =>
      $$MutableCommandAuditTableTableTableManager(
        _db.attachedDatabase,
        _db.mutableCommandAuditTable,
      );
}
