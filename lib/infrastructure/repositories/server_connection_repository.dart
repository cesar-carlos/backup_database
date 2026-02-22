import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/repositories/i_server_connection_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ServerConnectionRepository implements IServerConnectionRepository {
  ServerConnectionRepository(this._database);
  final AppDatabase _database;

  @override
  Future<rd.Result<List<ServerConnection>>> getAll() async {
    try {
      final list = await _database.serverConnectionDao.getAll();
      return rd.Success(list.map(_toEntity).toList());
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar conexões: $e'),
      );
    }
  }

  @override
  Future<rd.Result<ServerConnection>> getById(String id) async {
    try {
      final data = await _database.serverConnectionDao.getById(id);
      if (data == null) {
        return const rd.Failure(
          NotFoundFailure(message: 'Conexão não encontrada'),
        );
      }
      return rd.Success(_toEntity(data));
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar conexão: $e'),
      );
    }
  }

  @override
  Future<rd.Result<ServerConnection>> save(ServerConnection connection) async {
    try {
      final data = _toData(connection);
      await _database.serverConnectionDao.insertConnection(
        data.toCompanion(true),
      );
      return rd.Success(connection);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao salvar conexão: $e'),
      );
    }
  }

  @override
  Future<rd.Result<ServerConnection>> update(
    ServerConnection connection,
  ) async {
    try {
      final data = _toData(connection);
      await _database.serverConnectionDao.updateConnection(
        data.toCompanion(true),
      );
      return rd.Success(connection);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao atualizar conexão: $e'),
      );
    }
  }

  @override
  Future<rd.Result<void>> delete(String id) async {
    try {
      await _database.serverConnectionDao.deleteConnection(id);
      return const rd.Success(unit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar conexão: $e'),
      );
    }
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
