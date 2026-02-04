import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:backup_database/domain/repositories/i_server_credential_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ServerCredentialRepository implements IServerCredentialRepository {
  ServerCredentialRepository(this._database);
  final AppDatabase _database;

  @override
  Future<rd.Result<List<ServerCredential>>> getAll() async {
    try {
      final list = await _database.serverCredentialDao.getAll();
      return rd.Success(list.map(_toEntity).toList());
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar credenciais: $e'),
      );
    }
  }

  @override
  Future<rd.Result<ServerCredential>> getById(String id) async {
    try {
      final data = await _database.serverCredentialDao.getById(id);
      if (data == null) {
        return const rd.Failure(
          NotFoundFailure(message: 'Credencial não encontrada'),
        );
      }
      return rd.Success(_toEntity(data));
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar credencial: $e'),
      );
    }
  }

  @override
  Future<rd.Result<ServerCredential>> getByServerId(String serverId) async {
    try {
      final data = await _database.serverCredentialDao.getByServerId(serverId);
      if (data == null) {
        return const rd.Failure(
          NotFoundFailure(message: 'Credencial não encontrada para serverId'),
        );
      }
      return rd.Success(_toEntity(data));
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar credencial por serverId: $e'),
      );
    }
  }

  @override
  Future<rd.Result<ServerCredential>> save(ServerCredential credential) async {
    try {
      final data = _toData(credential);
      await _database.serverCredentialDao.insertCredential(data.toCompanion(true));
      return rd.Success(credential);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao salvar credencial: $e'),
      );
    }
  }

  @override
  Future<rd.Result<ServerCredential>> update(ServerCredential credential) async {
    try {
      final data = _toData(credential);
      await _database.serverCredentialDao.updateCredential(data.toCompanion(true));
      return rd.Success(credential);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao atualizar credencial: $e'),
      );
    }
  }

  @override
  Future<rd.Result<void>> delete(String id) async {
    try {
      await _database.serverCredentialDao.deleteCredential(id);
      return const rd.Success(unit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar credencial: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<ServerCredential>>> getActive() async {
    try {
      final list = await _database.serverCredentialDao.getActive();
      return rd.Success(list.map(_toEntity).toList());
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar credenciais ativas: $e'),
      );
    }
  }

  @override
  Future<rd.Result<void>> updateLastUsed(String id) async {
    try {
      await _database.serverCredentialDao.updateLastUsed(id);
      return const rd.Success(unit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao atualizar lastUsed: $e'),
      );
    }
  }

  @override
  Stream<List<ServerCredential>> watchAll() {
    return _database.serverCredentialDao.watchAll().map(
          (list) => list.map(_toEntity).toList(),
        );
  }

  ServerCredential _toEntity(ServerCredentialsTableData data) {
    return ServerCredential(
      id: data.id,
      serverId: data.serverId,
      passwordHash: data.passwordHash,
      name: data.name,
      isActive: data.isActive,
      createdAt: data.createdAt,
      lastUsedAt: data.lastUsedAt,
      description: data.description,
    );
  }

  ServerCredentialsTableData _toData(ServerCredential credential) {
    return ServerCredentialsTableData(
      id: credential.id,
      serverId: credential.serverId,
      passwordHash: credential.passwordHash,
      name: credential.name,
      isActive: credential.isActive,
      createdAt: credential.createdAt,
      lastUsedAt: credential.lastUsedAt,
      description: credential.description,
    );
  }
}
