// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sql_server_config_dao.dart';

// ignore_for_file: type=lint
mixin _$SqlServerConfigDaoMixin on DatabaseAccessor<AppDatabase> {
  $SqlServerConfigsTableTable get sqlServerConfigsTable =>
      attachedDatabase.sqlServerConfigsTable;
  SqlServerConfigDaoManager get managers => SqlServerConfigDaoManager(this);
}

class SqlServerConfigDaoManager {
  final _$SqlServerConfigDaoMixin _db;
  SqlServerConfigDaoManager(this._db);
  $$SqlServerConfigsTableTableTableManager get sqlServerConfigsTable =>
      $$SqlServerConfigsTableTableTableManager(
        _db.attachedDatabase,
        _db.sqlServerConfigsTable,
      );
}
