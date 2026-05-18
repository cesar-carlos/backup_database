// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_connection_dao.dart';

// ignore_for_file: type=lint
mixin _$ServerConnectionDaoMixin on DatabaseAccessor<AppDatabase> {
  $ServerConnectionsTableTable get serverConnectionsTable =>
      attachedDatabase.serverConnectionsTable;
  ServerConnectionDaoManager get managers => ServerConnectionDaoManager(this);
}

class ServerConnectionDaoManager {
  final _$ServerConnectionDaoMixin _db;
  ServerConnectionDaoManager(this._db);
  $$ServerConnectionsTableTableTableManager get serverConnectionsTable =>
      $$ServerConnectionsTableTableTableManager(
        _db.attachedDatabase,
        _db.serverConnectionsTable,
      );
}
