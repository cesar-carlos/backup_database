import 'package:backup_database/core/constants/secure_credential_keys.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/base_database_config_repository.dart';
import 'package:drift/drift.dart';

class SybaseConfigRepository
    extends BaseDatabaseConfigRepository<SybaseConfig, SybaseConfigsTableData>
    implements ISybaseConfigRepository {
  SybaseConfigRepository(
    super.database,
    super.secureCredentialService,
  );

  @override
  String credentialKeyFor(String configId) =>
      SecureCredentialKeys.sybasePasswordKey(configId);

  @override
  Future<List<SybaseConfigsTableData>> fetchAllRows() =>
      database.sybaseConfigDao.getAll();

  @override
  Future<List<SybaseConfigsTableData>> fetchEnabledRows() =>
      database.sybaseConfigDao.getEnabled();

  @override
  Future<SybaseConfigsTableData?> fetchRowById(String id) =>
      database.sybaseConfigDao.getById(id);

  @override
  Future<void> writeInsert(SybaseConfig config) =>
      database.sybaseConfigDao.insertConfig(_toCompanion(config));

  @override
  Future<void> writeUpdate(SybaseConfig config) =>
      database.sybaseConfigDao.updateConfig(_toCompanion(config));

  @override
  Future<void> writeDelete(String id) =>
      database.sybaseConfigDao.deleteConfig(id);

  @override
  Future<SybaseConfig> rowToEntity(SybaseConfigsTableData data) async {
    final password = await credentials.readPasswordOrEmpty(
      credentialKeyFor(data.id),
    );

    // Compatibilidade com bases legadas (v < 3) onde `database_name` podia
    // ficar vazio: a migração v3 já preenche com `server_name`, mas
    // mantemos o fallback aqui para qualquer linha residual.
    final databaseName = data.databaseName.isNotEmpty
        ? data.databaseName
        : data.serverName;

    return SybaseConfig(
      id: data.id,
      name: data.name,
      serverName: data.serverName,
      databaseName: DatabaseName(databaseName),
      databaseFile: data.databaseFile,
      port: PortNumber(data.port),
      username: data.username,
      password: password,
      enabled: data.enabled,
      isReplicationEnvironment: data.isReplicationEnvironment,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  // Senha real fica em `ISecureCredentialService` (chave
  // `sybase_password_<id>`); a coluna `password` da tabela permanece
  // string vazia por contrato com versões legadas.
  SybaseConfigsTableCompanion _toCompanion(SybaseConfig config) {
    return SybaseConfigsTableCompanion(
      id: Value(config.id),
      name: Value(config.name),
      serverName: Value(config.serverName),
      databaseName: Value(config.databaseNameValue),
      databaseFile: Value(config.databaseFile),
      port: Value(config.portValue),
      username: Value(config.username),
      password: const Value(''),
      enabled: Value(config.enabled),
      isReplicationEnvironment: Value(config.isReplicationEnvironment),
      createdAt: Value(config.createdAt),
      updatedAt: Value(config.updatedAt),
    );
  }
}
