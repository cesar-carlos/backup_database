import 'package:backup_database/core/constants/secure_credential_keys.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/base_database_config_repository.dart';
import 'package:drift/drift.dart';

class SqlServerConfigRepository
    extends
        BaseDatabaseConfigRepository<SqlServerConfig, SqlServerConfigsTableData>
    implements ISqlServerConfigRepository {
  SqlServerConfigRepository(
    super.database,
    super.secureCredentialService,
  );

  @override
  String credentialKeyFor(String configId) =>
      SecureCredentialKeys.sqlServerPasswordKey(configId);

  @override
  Future<List<SqlServerConfigsTableData>> fetchAllRows() =>
      database.sqlServerConfigDao.getAll();

  @override
  Future<List<SqlServerConfigsTableData>> fetchEnabledRows() =>
      database.sqlServerConfigDao.getEnabled();

  @override
  Future<SqlServerConfigsTableData?> fetchRowById(String id) =>
      database.sqlServerConfigDao.getById(id);

  @override
  Future<void> writeInsert(SqlServerConfig config) =>
      database.sqlServerConfigDao.insertConfig(_toCompanion(config));

  @override
  Future<void> writeUpdate(SqlServerConfig config) =>
      database.sqlServerConfigDao.updateConfig(_toCompanion(config));

  @override
  Future<void> writeDelete(String id) =>
      database.sqlServerConfigDao.deleteConfig(id);

  @override
  Future<SqlServerConfig> rowToEntity(SqlServerConfigsTableData data) async {
    final password = await credentials.readPasswordOrEmpty(
      credentialKeyFor(data.id),
    );

    return SqlServerConfig(
      id: data.id,
      name: data.name,
      server: data.server,
      database: DatabaseName(data.database),
      username: data.username,
      password: password,
      port: PortNumber(data.port),
      enabled: data.enabled,
      useWindowsAuth: data.useWindowsAuth,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  SqlServerConfigsTableCompanion _toCompanion(SqlServerConfig config) {
    return SqlServerConfigsTableCompanion(
      id: Value(config.id),
      name: Value(config.name),
      server: Value(config.server),
      database: Value(config.databaseValue),
      username: Value(config.username),
      password: const Value(''),
      port: Value(config.portValue),
      enabled: Value(config.enabled),
      useWindowsAuth: Value(config.useWindowsAuth),
      createdAt: Value(config.createdAt),
      updatedAt: Value(config.updatedAt),
    );
  }
}
