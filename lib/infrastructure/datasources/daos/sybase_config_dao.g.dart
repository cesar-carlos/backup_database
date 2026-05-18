// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sybase_config_dao.dart';

// ignore_for_file: type=lint
mixin _$SybaseConfigDaoMixin on DatabaseAccessor<AppDatabase> {
  $SybaseConfigsTableTable get sybaseConfigsTable =>
      attachedDatabase.sybaseConfigsTable;
  SybaseConfigDaoManager get managers => SybaseConfigDaoManager(this);
}

class SybaseConfigDaoManager {
  final _$SybaseConfigDaoMixin _db;
  SybaseConfigDaoManager(this._db);
  $$SybaseConfigsTableTableTableManager get sybaseConfigsTable =>
      $$SybaseConfigsTableTableTableManager(
        _db.attachedDatabase,
        _db.sybaseConfigsTable,
      );
}
