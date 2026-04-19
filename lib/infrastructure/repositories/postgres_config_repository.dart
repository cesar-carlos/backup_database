import 'dart:io';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/external/process/postgres_wal_slot_utils.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class PostgresConfigRepository implements IPostgresConfigRepository {
  PostgresConfigRepository(
    this._database,
    this._secureCredentialService,
    this._processService,
  );

  final AppDatabase _database;
  final ISecureCredentialService _secureCredentialService;
  final ps.ProcessService _processService;

  static const String _passwordKeyPrefix = 'postgres_password_';

  @override
  Future<rd.Result<List<PostgresConfig>>> getAll() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar configurações',
      action: () async {
        final configs = await _database.postgresConfigDao.getAll();
        return [for (final c in configs) await _toEntity(c)];
      },
    );
  }

  @override
  Future<rd.Result<PostgresConfig>> getById(String id) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar configuração',
      action: () async {
        final config = await _database.postgresConfigDao.getById(id);
        if (config == null) {
          throw const NotFoundFailure(message: 'Configuração não encontrada');
        }
        return _toEntity(config);
      },
    );
  }

  @override
  Future<rd.Result<PostgresConfig>> create(PostgresConfig config) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao criar configuração',
      action: () async {
        await _storePasswordOrThrow(config.id, config.password);
        final companion = _toCompanion(config);
        await _database.postgresConfigDao.insertConfig(companion);
        return config;
      },
    );
  }

  @override
  Future<rd.Result<PostgresConfig>> update(PostgresConfig config) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao atualizar configuração',
      action: () async {
        await _storePasswordOrThrow(config.id, config.password);
        final companion = _toCompanion(config);
        await _database.postgresConfigDao.updateConfig(companion);
        return config;
      },
    );
  }

  @override
  Future<rd.Result<void>> delete(String id) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao deletar configuração',
      action: () async {
        // Best-effort: tenta remover o replication slot antes de descartar
        // a config. Se a config nem existir mais, segue.
        final existingConfigResult = await getById(id);
        final existingConfig = existingConfigResult.getOrNull();
        if (existingConfig != null) {
          await _dropWalReplicationSlotBestEffort(existingConfig);
        }

        final passwordKey = '$_passwordKeyPrefix$id';
        await _secureCredentialService.deletePassword(key: passwordKey);
        await _database.postgresConfigDao.deleteConfig(id);
      },
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

    final environment = <String, String>{'PGPASSWORD': config.password};
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

  @override
  Future<rd.Result<List<PostgresConfig>>> getEnabled() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar configurações ativas',
      action: () async {
        final configs = await _database.postgresConfigDao.getEnabled();
        return [for (final c in configs) await _toEntity(c)];
      },
    );
  }

  Future<void> _storePasswordOrThrow(String id, String password) async {
    final passwordKey = '$_passwordKeyPrefix$id';
    final storeResult = await _secureCredentialService.storePassword(
      key: passwordKey,
      password: password,
    );
    if (storeResult.isError()) {
      throw storeResult.exceptionOrNull()!;
    }
  }

  Future<PostgresConfig> _toEntity(PostgresConfigsTableData data) async {
    final passwordKey = '$_passwordKeyPrefix${data.id}';
    final passwordResult = await _secureCredentialService.getPassword(
      key: passwordKey,
    );

    final password = passwordResult.getOrElse((_) => '');

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
