import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/server_credentials_table.dart';
import 'package:drift/drift.dart';

part 'server_credential_dao.g.dart';

@DriftAccessor(tables: [ServerCredentialsTable])
class ServerCredentialDao extends DatabaseAccessor<AppDatabase>
    with _$ServerCredentialDaoMixin {
  ServerCredentialDao(super.db);

  Future<List<ServerCredentialsTableData>> getAll() =>
      select(serverCredentialsTable).get();

  Future<ServerCredentialsTableData?> getById(String id) => (select(
    serverCredentialsTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<ServerCredentialsTableData?> getByServerId(String serverId) => (select(
    serverCredentialsTable,
  )..where((t) => t.serverId.equals(serverId))).getSingleOrNull();

  Future<int> insertCredential(ServerCredentialsTableCompanion credential) =>
      into(serverCredentialsTable).insert(credential);

  Future<bool> updateCredential(ServerCredentialsTableCompanion credential) =>
      update(serverCredentialsTable).replace(credential);

  Future<int> deleteCredential(String id) =>
      (delete(serverCredentialsTable)..where((t) => t.id.equals(id))).go();

  Future<List<ServerCredentialsTableData>> getActive() => (select(
    serverCredentialsTable,
  )..where((t) => t.isActive.equals(true))).get();

  Future<int> updateLastUsed(String id) {
    return (update(
      serverCredentialsTable,
    )..where((t) => t.id.equals(id))).write(
      ServerCredentialsTableCompanion(
        lastUsedAt: Value(DateTime.now()),
      ),
    );
  }

  Stream<List<ServerCredentialsTableData>> watchAll() =>
      select(serverCredentialsTable).watch();
}
