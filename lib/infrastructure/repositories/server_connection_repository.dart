import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/repositories/i_server_connection_repository.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:backup_database/infrastructure/repositories/secure_credential_helper.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// §audit-2026-05-28 (P0): a senha que o cliente usa para autenticar
/// no socket do servidor **NUNCA** mais deve ser armazenada em texto
/// claro na tabela `server_connections`. Toda escrita persiste a senha
/// em secure storage device-bound (DPAPI no Windows via
/// `MachineScopeSecureCredentialService`) e zera a coluna do SQLite.
/// Leituras buscam transparentemente do vault e — quando encontram
/// uma linha legada com plaintext — migram para o vault on the fly
/// para que a próxima leitura não dependa do fallback.
class ServerConnectionRepository implements IServerConnectionRepository {
  ServerConnectionRepository(
    this._database,
    ISecureCredentialService secureCredentialService,
  ) : _credentials = SecureCredentialHelper(secureCredentialService);

  final AppDatabase _database;
  final SecureCredentialHelper _credentials;

  /// Convenção de chave do vault para cada conexão salva. Prefixo
  /// dedicado evita colisão com `database_config_<id>`, `oauth_<id>`,
  /// etc. já usados por outros repositórios.
  static String _credentialKey(String connectionId) =>
      'server_connection_$connectionId';

  @override
  Future<rd.Result<List<ServerConnection>>> getAll() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar conexões',
      action: () async {
        final list = await _database.serverConnectionDao.getAll();
        return [for (final data in list) await _toEntity(data)];
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
        await _credentials.storePasswordOrThrow(
          key: _credentialKey(connection.id),
          password: connection.password,
        );
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
        await _credentials.storePasswordOrThrow(
          key: _credentialKey(connection.id),
          password: connection.password,
        );
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
      action: () async {
        await _credentials.deletePassword(_credentialKey(id));
        await _database.serverConnectionDao.deleteConnection(id);
      },
    );
  }

  @override
  Stream<List<ServerConnection>> watchAll() {
    // O `asyncMap` garante que cada snapshot do Drift seja mapeado em
    // série, lendo o vault apenas uma vez por linha antes de emitir
    // para os listeners. Sem isso, listeners de UI rebuildariam com
    // senhas vazias enquanto o vault ainda respondia.
    return _database.serverConnectionDao.watchAll().asyncMap(
      (list) async => [for (final data in list) await _toEntity(data)],
    );
  }

  /// Lê uma linha do Drift e a converte em entidade. Quando a coluna
  /// `password` ainda contém texto claro (legado pré-correção P0),
  /// migra **silenciosamente** o segredo para o vault e zera a
  /// coluna no SQLite. Falha de migração não bloqueia a leitura — só
  /// emite warning para que a inconsistência seja diagnosticável.
  Future<ServerConnection> _toEntity(ServerConnectionsTableData data) async {
    final key = _credentialKey(data.id);
    final legacyPlaintext = data.password;
    String password;
    if (legacyPlaintext.isNotEmpty) {
      // Caminho de migração: move para o vault e zera a coluna.
      password = legacyPlaintext;
      try {
        await _credentials.storePasswordOrThrow(
          key: key,
          password: legacyPlaintext,
        );
        await _database.serverConnectionDao.updateConnection(
          ServerConnectionsTableData(
            id: data.id,
            name: data.name,
            serverId: data.serverId,
            host: data.host,
            port: data.port,
            password: '',
            isOnline: data.isOnline,
            lastConnectedAt: data.lastConnectedAt,
            createdAt: data.createdAt,
            updatedAt: data.updatedAt,
          ).toCompanion(true),
        );
        LoggerService.info(
          '[server_connections] Senha legada migrada para vault (id=${data.id})',
        );
      } on Object catch (e, s) {
        LoggerService.warning(
          '[server_connections] Falha ao migrar senha legada para vault '
          '(id=${data.id}); a linha permanece com plaintext até a próxima '
          'leitura: $e',
          e,
          s,
        );
      }
    } else {
      password = await _credentials.readPasswordOrEmpty(key);
    }

    return ServerConnection(
      id: data.id,
      name: data.name,
      serverId: data.serverId,
      host: data.host,
      port: data.port,
      password: password,
      isOnline: data.isOnline,
      lastConnectedAt: data.lastConnectedAt,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  /// Sempre persiste `password = ''` no SQLite. A senha real fica
  /// exclusivamente no vault (chave `_credentialKey(id)`).
  ServerConnectionsTableData _toData(ServerConnection connection) {
    return ServerConnectionsTableData(
      id: connection.id,
      name: connection.name,
      serverId: connection.serverId,
      host: connection.host,
      port: connection.port,
      password: '',
      isOnline: connection.isOnline,
      lastConnectedAt: connection.lastConnectedAt,
      createdAt: connection.createdAt,
      updatedAt: connection.updatedAt,
    );
  }
}
