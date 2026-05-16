import 'dart:io';

import 'package:backup_database/core/constants/secure_credential_keys.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/external/process/postgres_wal_slot_utils.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:backup_database/infrastructure/repositories/base_database_config_repository.dart';
import 'package:drift/drift.dart';

class PostgresConfigRepository
    extends
        BaseDatabaseConfigRepository<PostgresConfig, PostgresConfigsTableData>
    implements IPostgresConfigRepository {
  PostgresConfigRepository(
    super.database,
    super.secureCredentialService,
    this._processService,
  );

  final ps.ProcessService _processService;

  @override
  String credentialKeyFor(String configId) =>
      SecureCredentialKeys.postgresPasswordKey(configId);

  @override
  Future<List<PostgresConfigsTableData>> fetchAllRows() =>
      database.postgresConfigDao.getAll();

  @override
  Future<List<PostgresConfigsTableData>> fetchEnabledRows() =>
      database.postgresConfigDao.getEnabled();

  @override
  Future<PostgresConfigsTableData?> fetchRowById(String id) =>
      database.postgresConfigDao.getById(id);

  @override
  Future<void> writeInsert(PostgresConfig config) =>
      database.postgresConfigDao.insertConfig(_toCompanion(config));

  @override
  Future<void> writeUpdate(PostgresConfig config) =>
      database.postgresConfigDao.updateConfig(_toCompanion(config));

  @override
  Future<void> writeDelete(String id) =>
      database.postgresConfigDao.deleteConfig(id);

  @override
  Future<void> onBeforeDelete(String id) async {
    final row = await database.postgresConfigDao.getById(id);
    if (row == null) {
      return;
    }
    final config = await rowToEntity(row);
    await _dropWalReplicationSlotBestEffort(config);
  }

  @override
  Future<PostgresConfig> rowToEntity(PostgresConfigsTableData data) async {
    final password = await credentials.readPasswordOrEmpty(
      credentialKeyFor(data.id),
    );

    return PostgresConfig(
      id: data.id,
      name: data.name,
      host: data.host,
      port: PortNumber(data.port),
      database: DatabaseName(data.database),
      username: data.username,
      password: password,
      enabled: data.enabled,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  Future<void> _dropWalReplicationSlotBestEffort(PostgresConfig config) async {
    final useSlot = PostgresWalSlotUtils.isWalSlotEnabled(
      environment: Platform.environment,
    );
    if (!useSlot) {
      return;
    }

    final slotName = PostgresWalSlotUtils.resolveWalSlotName(
      config: config,
      environment: Platform.environment,
    );
    final escapedSlotName = slotName.replaceAll("'", "''");
    final dropSlotSql =
        "SELECT pg_drop_replication_slot('$escapedSlotName') "
        "WHERE EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = '$escapedSlotName');";

    final arguments = <String>[
      '-h',
      config.host,
      '-p',
      config.portValue.toString(),
      '-U',
      config.username,
      '-d',
      config.databaseValue,
      '-c',
      dropSlotSql,
    ];

    final environment = <String, String>{
      'PGPASSWORD': config.password,
    };
    final result = await _processService.run(
      executable: 'psql',
      arguments: arguments,
      environment: environment,
      timeout: const Duration(seconds: 30),
    );

    result.fold(
      (processResult) {
        if (processResult.isSuccess) {
          LoggerService.info(
            'Replication slot removido no delete da configuracao PostgreSQL: $slotName',
          );
          return;
        }

        final output = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;
        LoggerService.warning(
          'Falha ao remover replication slot no delete da configuracao. '
          'Slot: $slotName. Limpeza manual recomendada via '
          "SELECT pg_drop_replication_slot('$slotName'). Erro: $output",
        );
      },
      (failure) {
        LoggerService.warning(
          'Erro ao remover replication slot no delete da configuracao. '
          'Slot: $slotName. Limpeza manual recomendada via '
          "SELECT pg_drop_replication_slot('$slotName'). Erro: $failure",
        );
      },
    );
  }

  PostgresConfigsTableCompanion _toCompanion(PostgresConfig config) {
    return PostgresConfigsTableCompanion(
      id: Value(config.id),
      name: Value(config.name),
      host: Value(config.host),
      port: Value(config.portValue),
      database: Value(config.databaseValue),
      username: Value(config.username),
      password: const Value(''),
      enabled: Value(config.enabled),
      createdAt: Value(config.createdAt),
      updatedAt: Value(config.updatedAt),
    );
  }
}
