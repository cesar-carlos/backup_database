// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_credential_dao.dart';

// ignore_for_file: type=lint
mixin _$ServerCredentialDaoMixin on DatabaseAccessor<AppDatabase> {
  $ServerCredentialsTableTable get serverCredentialsTable =>
      attachedDatabase.serverCredentialsTable;
  ServerCredentialDaoManager get managers => ServerCredentialDaoManager(this);
}

class ServerCredentialDaoManager {
  final _$ServerCredentialDaoMixin _db;
  ServerCredentialDaoManager(this._db);
  $$ServerCredentialsTableTableTableManager get serverCredentialsTable =>
      $$ServerCredentialsTableTableTableManager(
        _db.attachedDatabase,
        _db.serverCredentialsTable,
      );
}
