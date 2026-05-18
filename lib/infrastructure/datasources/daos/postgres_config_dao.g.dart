// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'postgres_config_dao.dart';

// ignore_for_file: type=lint
mixin _$PostgresConfigDaoMixin on DatabaseAccessor<AppDatabase> {
  $PostgresConfigsTableTable get postgresConfigsTable =>
      attachedDatabase.postgresConfigsTable;
  PostgresConfigDaoManager get managers => PostgresConfigDaoManager(this);
}

class PostgresConfigDaoManager {
  final _$PostgresConfigDaoMixin _db;
  PostgresConfigDaoManager(this._db);
  $$PostgresConfigsTableTableTableManager get postgresConfigsTable =>
      $$PostgresConfigsTableTableTableManager(
        _db.attachedDatabase,
        _db.postgresConfigsTable,
      );
}
