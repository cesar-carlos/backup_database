import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/server_connections_table.dart';
import 'package:drift/drift.dart';

part 'server_connection_dao.g.dart';

@DriftAccessor(tables: [ServerConnectionsTable])
class ServerConnectionDao extends DatabaseAccessor<AppDatabase>
    with _$ServerConnectionDaoMixin {
  ServerConnectionDao(super.db);

  Future<List<ServerConnectionsTableData>> getAll() =>
      select(serverConnectionsTable).get();

  Future<ServerConnectionsTableData?> getById(String id) => (select(
    serverConnectionsTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertConnection(ServerConnectionsTableCompanion connection) =>
      into(serverConnectionsTable).insert(connection);

  Future<bool> updateConnection(ServerConnectionsTableCompanion connection) =>
      update(serverConnectionsTable).replace(connection);

  Future<int> deleteConnection(String id) =>
      (delete(serverConnectionsTable)..where((t) => t.id.equals(id))).go();

  Future<List<ServerConnectionsTableData>> getOnlineConnections() => (select(
    serverConnectionsTable,
  )..where((t) => t.isOnline.equals(true))).get();

  Future<int> updateOnlineStatus(String id, bool isOnline) {
    return (update(
      serverConnectionsTable,
    )..where((t) => t.id.equals(id))).write(
      ServerConnectionsTableCompanion(
        isOnline: Value(isOnline),
        lastConnectedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Stream<List<ServerConnectionsTableData>> watchAll() =>
      select(serverConnectionsTable).watch();
}
