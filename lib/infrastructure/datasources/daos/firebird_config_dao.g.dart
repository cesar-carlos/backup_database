// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'firebird_config_dao.dart';

// ignore_for_file: type=lint
mixin _$FirebirdConfigDaoMixin on DatabaseAccessor<AppDatabase> {
  $FirebirdConfigsTableTable get firebirdConfigsTable =>
      attachedDatabase.firebirdConfigsTable;
  FirebirdConfigDaoManager get managers => FirebirdConfigDaoManager(this);
}

class FirebirdConfigDaoManager {
  final _$FirebirdConfigDaoMixin _db;
  FirebirdConfigDaoManager(this._db);
  $$FirebirdConfigsTableTableTableManager get firebirdConfigsTable =>
      $$FirebirdConfigsTableTableTableManager(
        _db.attachedDatabase,
        _db.firebirdConfigsTable,
      );
}
