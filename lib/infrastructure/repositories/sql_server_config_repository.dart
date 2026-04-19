import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SqlServerConfigRepository implements ISqlServerConfigRepository {
  SqlServerConfigRepository(
    this._database,
    this._secureCredentialService,
  );

  final AppDatabase _database;
  final ISecureCredentialService _secureCredentialService;

  static const String _passwordKeyPrefix = 'sql_server_password_';

  @override
  Future<rd.Result<List<SqlServerConfig>>> getAll() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar configurações',
      action: () async {
        final configs = await _database.sqlServerConfigDao.getAll();
        return [for (final c in configs) await _toEntity(c)];
      },
    );
  }

  @override
  Future<rd.Result<SqlServerConfig>> getById(String id) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar configuração',
      action: () async {
        final config = await _database.sqlServerConfigDao.getById(id);
        if (config == null) {
          // `NotFoundFailure` é um `Failure`, então o `RepositoryGuard.run`
          // o propaga sem reembrulhar (passthrough no `on Failure catch`).
          throw const NotFoundFailure(message: 'Configuração não encontrada');
        }
        return _toEntity(config);
      },
    );
  }

  @override
  Future<rd.Result<SqlServerConfig>> create(SqlServerConfig config) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao criar configuração',
      action: () async {
        await _storePasswordOrThrow(config.id, config.password);
        final companion = _toCompanion(config);
        await _database.sqlServerConfigDao.insertConfig(companion);
        return config;
      },
    );
  }

  @override
  Future<rd.Result<SqlServerConfig>> update(SqlServerConfig config) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao atualizar configuração',
      action: () async {
        await _storePasswordOrThrow(config.id, config.password);
        final companion = _toCompanion(config);
        await _database.sqlServerConfigDao.updateConfig(companion);
        return config;
      },
    );
  }

  @override
  Future<rd.Result<void>> delete(String id) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao deletar configuração',
      action: () async {
        final passwordKey = '$_passwordKeyPrefix$id';
        await _secureCredentialService.deletePassword(key: passwordKey);
        await _database.sqlServerConfigDao.deleteConfig(id);
      },
    );
  }

  @override
  Future<rd.Result<List<SqlServerConfig>>> getEnabled() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar configurações ativas',
      action: () async {
        final configs = await _database.sqlServerConfigDao.getEnabled();
        return [for (final c in configs) await _toEntity(c)];
      },
    );
  }

  /// Centraliza o "store password" — antes era reimplementado em `create`
  /// e `update`. Lança em caso de falha para que o `RepositoryGuard`
  /// converta no `Failure` com a mensagem apropriada.
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

  Future<SqlServerConfig> _toEntity(SqlServerConfigsTableData data) async {
    final passwordKey = '$_passwordKeyPrefix${data.id}';
    final passwordResult = await _secureCredentialService.getPassword(
      key: passwordKey,
    );

    final password = passwordResult.getOrElse((_) => '');

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
