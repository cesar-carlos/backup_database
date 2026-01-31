import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/encryption/encryption.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class PostgresConfigRepository implements IPostgresConfigRepository {
  PostgresConfigRepository(this._database);
  final AppDatabase _database;

  @override
  Future<rd.Result<List<PostgresConfig>>> getAll() async {
    try {
      final configs = await _database.postgresConfigDao.getAll();
      final entities = configs.map(_toEntity).toList();
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
      return rd.Success(_toEntity(config));
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar configuração: $e'),
      );
    }
  }

  @override
  Future<rd.Result<PostgresConfig>> create(PostgresConfig config) async {
    try {
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
      final entities = configs.map(_toEntity).toList();
      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar configurações ativas: $e'),
      );
    }
  }

  PostgresConfig _toEntity(PostgresConfigsTableData data) {
    final decryptedPassword = EncryptionService.decrypt(data.password);

    return PostgresConfig(
      id: data.id,
      name: data.name,
      host: data.host,
      port: data.port,
      database: data.database,
      username: data.username,
      password: decryptedPassword,
      enabled: data.enabled,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  PostgresConfigsTableCompanion _toCompanion(PostgresConfig config) {
    final encryptedPassword = EncryptionService.encrypt(config.password);

    return PostgresConfigsTableCompanion(
      id: Value(config.id),
      name: Value(config.name),
      host: Value(config.host),
      port: Value(config.port),
      database: Value(config.database),
      username: Value(config.username),
      password: Value(encryptedPassword),
      enabled: Value(config.enabled),
      createdAt: Value(config.createdAt),
      updatedAt: Value(config.updatedAt),
    );
  }
}
