import 'package:backup_database/core/constants/secure_credential_keys.dart';
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

  @override
  Future<FirebirdConfig> rowToEntity(FirebirdConfigsTableData data) async {
    final password = await credentials.readPasswordOrEmpty(
      credentialKeyFor(data.id),
    );

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
      cryptKey: data.cryptKey,
      enabled: data.enabled,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

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
      cryptKey: Value(config.cryptKey),
      enabled: Value(config.enabled),
      createdAt: Value(config.createdAt),
      updatedAt: Value(config.updatedAt),
    );
  }
}
