import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/repositories/i_server_connection_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ServerConnectionRepository implements IServerConnectionRepository {
  ServerConnectionRepository(this._database);
  final AppDatabase _database;

  @override
  Future<rd.Result<List<ServerConnection>>> getAll() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar conexões',
      action: () async {
        final list = await _database.serverConnectionDao.getAll();
        return list.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<ServerConnection>> getById(String id) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar conexão',
      action: () async {
        final data = await _database.serverConnectionDao.getById(id);
        if (data == null) {
          throw const NotFoundFailure(message: 'Conexão não encontrada');
        }
        return _toEntity(data);
      },
    );
  }

  @override
  Future<rd.Result<ServerConnection>> save(ServerConnection connection) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao salvar conexão',
      action: () async {
        final data = _toData(connection);
        await _database.serverConnectionDao.insertConnection(
          data.toCompanion(true),
        );
        return connection;
      },
    );
  }

  @override
  Future<rd.Result<ServerConnection>> update(ServerConnection connection) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao atualizar conexão',
      action: () async {
        final data = _toData(connection);
        await _database.serverConnectionDao.updateConnection(
          data.toCompanion(true),
        );
        return connection;
      },
    );
  }

  @override
  Future<rd.Result<void>> delete(String id) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao deletar conexão',
      action: () => _database.serverConnectionDao.deleteConnection(id),
    );
  }

  @override
  Stream<List<ServerConnection>> watchAll() {
    return _database.serverConnectionDao.watchAll().map(
      (list) => list.map(_toEntity).toList(),
    );
  }

  ServerConnection _toEntity(ServerConnectionsTableData data) {
    return ServerConnection(
      id: data.id,
      name: data.name,
      serverId: data.serverId,
      host: data.host,
      port: data.port,
      password: data.password,
      isOnline: data.isOnline,
      lastConnectedAt: data.lastConnectedAt,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  ServerConnectionsTableData _toData(ServerConnection connection) {
    return ServerConnectionsTableData(
      id: connection.id,
      name: connection.name,
      serverId: connection.serverId,
      host: connection.host,
      port: connection.port,
      password: connection.password,
      isOnline: connection.isOnline,
      lastConnectedAt: connection.lastConnectedAt,
      createdAt: connection.createdAt,
      updatedAt: connection.updatedAt,
    );
  }
}
