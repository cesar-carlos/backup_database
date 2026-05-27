import 'package:backup_database/core/constants/secure_credential_keys.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/repositories/i_firebird_config_repository.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/base_database_config_repository.dart';
import 'package:drift/drift.dart';

class FirebirdConfigRepository
    extends
        BaseDatabaseConfigRepository<FirebirdConfig, FirebirdConfigsTableData>
    implements IFirebirdConfigRepository {
  FirebirdConfigRepository(super.database, super.secureCredentialService);

  String _cryptKeyKeyFor(String configId) =>
      SecureCredentialKeys.firebirdCryptKeyKey(configId);

  @override
  String credentialKeyFor(String configId) =>
      SecureCredentialKeys.firebirdPasswordKey(configId);

  @override
  Future<List<FirebirdConfigsTableData>> fetchAllRows() =>
      database.firebirdConfigDao.getAll();

  @override
  Future<List<FirebirdConfigsTableData>> fetchEnabledRows() =>
      database.firebirdConfigDao.getEnabled();

  @override
  Future<FirebirdConfigsTableData?> fetchRowById(String id) =>
      database.firebirdConfigDao.getById(id);

  @override
  Future<void> writeInsert(FirebirdConfig config) =>
      database.firebirdConfigDao.insertConfig(_toCompanion(config));

  @override
  Future<void> writeUpdate(FirebirdConfig config) =>
      database.firebirdConfigDao.updateConfig(_toCompanion(config));

  @override
  Future<void> writeDelete(String id) =>
      database.firebirdConfigDao.deleteConfig(id);

  // Segredos adicionais ao password padrao: cryptKey via secure storage.
  // Ver hook em `BaseDatabaseConfigRepository.onWriteAdditionalSecrets`.
  @override
  Future<void> onWriteAdditionalSecrets(FirebirdConfig config) =>
      _storeCryptKey(config);

  @override
  Future<void> onDeleteAdditionalSecrets(String id) => _deleteCryptKey(id);

  @override
  Future<FirebirdConfig> rowToEntity(FirebirdConfigsTableData data) async {
    final password = await credentials.readPasswordOrEmpty(
      credentialKeyFor(data.id),
    );

    // Migracao transparente da `cryptKey`:
    // - Estado novo: secure storage tem o segredo, coluna DB esta vazia.
    // - Estado legado: secure storage vazio, coluna DB tem o segredo.
    //   Nesse caso movemos para secure storage agora e limpamos a
    //   coluna, para que a base local nao continue a armazenar a chave
    //   em texto puro. Falhas de I/O nao bloqueiam a leitura: caem em
    //   warning e a entidade segue com o valor legado, ate a proxima
    //   tentativa.
    var cryptKey = await credentials.readPasswordOrEmpty(
      _cryptKeyKeyFor(data.id),
    );
    if (cryptKey.isEmpty && data.cryptKey.isNotEmpty) {
      cryptKey = data.cryptKey;
      try {
        await credentials.storePasswordOrThrow(
          key: _cryptKeyKeyFor(data.id),
          password: data.cryptKey,
        );
        // UPDATE parcial — Drift `replace` exigiria o row inteiro; aqui
        // queremos apenas zerar a coluna cryptKey (a senha do utilizador
        // ja vive em secure storage e os outros campos nao mudam).
        await (database.update(database.firebirdConfigsTable)
              ..where((t) => t.id.equals(data.id)))
            .write(const FirebirdConfigsTableCompanion(cryptKey: Value('')));
        LoggerService.info(
          'Firebird cryptKey migrada para secure storage '
          '(config ${data.id}); coluna SQLite limpa.',
        );
      } on Object catch (e, s) {
        LoggerService.warning(
          'Falha ao migrar Firebird cryptKey para secure storage '
          '(config ${data.id}); valor legado mantido na coluna SQLite.',
          e,
          s,
        );
      }
    }

    return FirebirdConfig(
      id: data.id,
      name: data.name,
      host: data.host,
      port: PortNumber(data.port),
      databaseFile: data.databaseFile,
      aliasName: data.aliasName,
      useEmbedded: data.useEmbedded,
      clientLibraryPath: data.clientLibraryPath,
      serverVersionHint: FirebirdServerVersionHint.parse(
        data.serverVersionHint,
      ),
      serviceManagerMode: FirebirdServiceManagerMode.parse(
        data.serviceManagerMode,
      ),
      username: data.username,
      password: password,
      cryptKey: cryptKey,
      enabled: data.enabled,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  Future<void> _storeCryptKey(FirebirdConfig config) {
    return credentials.storePasswordOrThrow(
      key: _cryptKeyKeyFor(config.id),
      password: config.cryptKey,
    );
  }

  Future<void> _deleteCryptKey(String id) =>
      credentials.deletePassword(_cryptKeyKeyFor(id));

  FirebirdConfigsTableCompanion _toCompanion(FirebirdConfig config) {
    return FirebirdConfigsTableCompanion(
      id: Value(config.id),
      name: Value(config.name),
      host: Value(config.host),
      port: Value(config.portValue),
      databaseFile: Value(config.databaseFile),
      aliasName: Value(config.aliasName),
      useEmbedded: Value(config.useEmbedded),
      clientLibraryPath: Value(config.clientLibraryPath),
      serverVersionHint: Value(config.serverVersionHint.wireValue),
      serviceManagerMode: Value(config.serviceManagerMode.wireValue),
      username: Value(config.username),
      password: const Value(''),
      // Coluna SQLite fica sempre vazia em writes novos: o segredo
      // real vive em secure storage. Mantida na tabela so para
      // compatibilidade de schema (migracao do legado em `rowToEntity`).
      cryptKey: const Value(''),
      enabled: Value(config.enabled),
      createdAt: Value(config.createdAt),
      updatedAt: Value(config.updatedAt),
    );
  }
}
