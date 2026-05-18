// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_config_dao.dart';

// ignore_for_file: type=lint
mixin _$EmailConfigDaoMixin on DatabaseAccessor<AppDatabase> {
  $EmailConfigsTableTable get emailConfigsTable =>
      attachedDatabase.emailConfigsTable;
  EmailConfigDaoManager get managers => EmailConfigDaoManager(this);
}

class EmailConfigDaoManager {
  final _$EmailConfigDaoMixin _db;
  EmailConfigDaoManager(this._db);
  $$EmailConfigsTableTableTableManager get emailConfigsTable =>
      $$EmailConfigsTableTableTableManager(
        _db.attachedDatabase,
        _db.emailConfigsTable,
      );
}
