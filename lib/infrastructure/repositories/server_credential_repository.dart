import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:backup_database/domain/repositories/i_server_credential_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ServerCredentialRepository implements IServerCredentialRepository {
  ServerCredentialRepository(this._database);
  final AppDatabase _database;

  @override
  Future<rd.Result<List<ServerCredential>>> getAll() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar credenciais',
      action: () async {
        final list = await _database.serverCredentialDao.getAll();
        return list.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<ServerCredential>> getById(String id) {
    return _findOrNotFound(
      errorMessage: 'Erro ao buscar credencial',
      notFoundMessage: 'Credencial não encontrada',
      fetch: () => _database.serverCredentialDao.getById(id),
    );
  }

  @override
  Future<rd.Result<ServerCredential>> getByServerId(String serverId) {
    return _findOrNotFound(
      errorMessage: 'Erro ao buscar credencial por serverId',
      notFoundMessage: 'Credencial não encontrada para serverId',
      fetch: () => _database.serverCredentialDao.getByServerId(serverId),
    );
  }

  @override
  Future<rd.Result<ServerCredential>> save(ServerCredential credential) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao salvar credencial',
      action: () async {
        final data = _toData(credential);
        await _database.serverCredentialDao.insertCredential(
          data.toCompanion(true),
        );
        return credential;
      },
    );
  }

  @override
  Future<rd.Result<ServerCredential>> update(ServerCredential credential) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao atualizar credencial',
      action: () async {
        final data = _toData(credential);
        await _database.serverCredentialDao.updateCredential(
          data.toCompanion(true),
        );
        return credential;
      },
    );
  }

  @override
  Future<rd.Result<void>> delete(String id) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao deletar credencial',
      action: () => _database.serverCredentialDao.deleteCredential(id),
    );
  }

  @override
  Future<rd.Result<List<ServerCredential>>> getActive() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar credenciais ativas',
      action: () async {
        final list = await _database.serverCredentialDao.getActive();
        return list.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<void>> updateLastUsed(String id) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao atualizar lastUsed',
      action: () => _database.serverCredentialDao.updateLastUsed(id),
    );
  }

  @override
  Stream<List<ServerCredential>> watchAll() {
    return _database.serverCredentialDao.watchAll().map(
      (list) => list.map(_toEntity).toList(),
    );
  }

  /// Helper unificado para `getById` e `getByServerId`. Antes os dois
  /// métodos tinham try/catch idênticos, divergindo apenas no DAO chamado.
  Future<rd.Result<ServerCredential>> _findOrNotFound({
    required String errorMessage,
    required String notFoundMessage,
    required Future<ServerCredentialsTableData?> Function() fetch,
  }) {
    return RepositoryGuard.run(
      errorMessage: errorMessage,
      action: () async {
        final data = await fetch();
        if (data == null) {
          // `NotFoundFailure` (subtipo de `Failure`) passa direto pelo
          // `RepositoryGuard.run` (branch `on Failure catch`).
          throw NotFoundFailure(message: notFoundMessage);
        }
        return _toEntity(data);
      },
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
