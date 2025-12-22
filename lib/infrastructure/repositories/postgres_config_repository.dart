import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../core/core.dart';
import '../../core/encryption/encryption.dart';
import '../../domain/entities/postgres_config.dart';
import '../../domain/repositories/i_postgres_config_repository.dart';
import '../datasources/local/database.dart';

class PostgresConfigRepository implements IPostgresConfigRepository {
  final AppDatabase _database;

  PostgresConfigRepository(this._database);

  @override
  Future<rd.Result<List<PostgresConfig>>> getAll() async {
    try {
      final configs = await _database.postgresConfigDao.getAll();
      final entities = configs.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
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
        return rd.Failure(
          NotFoundFailure(message: 'Configuração não encontrada'),
        );
      }
      return rd.Success(_toEntity(config));
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar configuração: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<PostgresConfig>>> getEnabled() async {
    try {
      final configs = await _database.postgresConfigDao.getEnabled();
      final entities = configs.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
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
