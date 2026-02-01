import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class PostgresConfigRepository implements IPostgresConfigRepository {
  PostgresConfigRepository(
    this._database,
    this._secureCredentialService,
  );

  final AppDatabase _database;
  final ISecureCredentialService _secureCredentialService;

  static const String _passwordKeyPrefix = 'postgres_password_';

  @override
  Future<rd.Result<List<PostgresConfig>>> getAll() async {
    try {
      final configs = await _database.postgresConfigDao.getAll();
      final entities = <PostgresConfig>[];
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
  Future<rd.Result<PostgresConfig>> getById(String id) async {
    try {
      final config = await _database.postgresConfigDao.getById(id);
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
  Future<rd.Result<PostgresConfig>> create(PostgresConfig config) async {
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
      await _database.postgresConfigDao.insertConfig(companion);
      return rd.Success(config);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao criar configuração: $e'),
      );
    }
  }

  @override
  Future<rd.Result<PostgresConfig>> update(PostgresConfig config) async {
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
      await _database.postgresConfigDao.updateConfig(companion);
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
      await _database.postgresConfigDao.deleteConfig(id);
      return const rd.Success(unit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar configuração: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<PostgresConfig>>> getEnabled() async {
    try {
      final configs = await _database.postgresConfigDao.getEnabled();
      final entities = <PostgresConfig>[];
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
