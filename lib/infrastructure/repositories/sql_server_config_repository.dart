import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
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
  Future<rd.Result<List<SqlServerConfig>>> getAll() async {
    try {
      final configs = await _database.sqlServerConfigDao.getAll();
      final entities = <SqlServerConfig>[];
      for (final config in configs) {
        final entity = await _toEntity(config);
        entities.add(entity);
      }
      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar configurações: $e'),
      );
    }
  }

  @override
  Future<rd.Result<SqlServerConfig>> getById(String id) async {
    try {
      final config = await _database.sqlServerConfigDao.getById(id);
      if (config == null) {
        return const rd.Failure(
          NotFoundFailure(message: 'Configuração não encontrada'),
        );
      }
      final entity = await _toEntity(config);
      return rd.Success(entity);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar configuração: $e'),
      );
    }
  }

  @override
  Future<rd.Result<SqlServerConfig>> create(SqlServerConfig config) async {
    try {
      final passwordKey = '$_passwordKeyPrefix${config.id}';
      final storeResult = await _secureCredentialService.storePassword(
        key: passwordKey,
        password: config.password,
      );

      if (storeResult.isError()) {
        return rd.Failure(storeResult.exceptionOrNull()!);
      }

      final companion = _toCompanion(config);
      await _database.sqlServerConfigDao.insertConfig(companion);
      return rd.Success(config);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao criar configuração: $e'),
      );
    }
  }

  @override
  Future<rd.Result<SqlServerConfig>> update(SqlServerConfig config) async {
    try {
      final passwordKey = '$_passwordKeyPrefix${config.id}';
      final storeResult = await _secureCredentialService.storePassword(
        key: passwordKey,
        password: config.password,
      );

      if (storeResult.isError()) {
        return rd.Failure(storeResult.exceptionOrNull()!);
      }

      final companion = _toCompanion(config);
      await _database.sqlServerConfigDao.updateConfig(companion);
      return rd.Success(config);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao atualizar configuração: $e'),
      );
    }
  }

  @override
  Future<rd.Result<void>> delete(String id) async {
    try {
      final passwordKey = '$_passwordKeyPrefix$id';
      await _secureCredentialService.deletePassword(key: passwordKey);
      await _database.sqlServerConfigDao.deleteConfig(id);
      return const rd.Success(unit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar configuração: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<SqlServerConfig>>> getEnabled() async {
    try {
      final configs = await _database.sqlServerConfigDao.getEnabled();
      final entities = <SqlServerConfig>[];
      for (final config in configs) {
        final entity = await _toEntity(config);
        entities.add(entity);
      }
      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar configurações ativas: $e'),
      );
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
