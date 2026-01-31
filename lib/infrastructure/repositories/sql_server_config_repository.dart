import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/encryption/encryption.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SqlServerConfigRepository implements ISqlServerConfigRepository {
  SqlServerConfigRepository(this._database);
  final AppDatabase _database;

  @override
  Future<rd.Result<List<SqlServerConfig>>> getAll() async {
    try {
      final configs = await _database.sqlServerConfigDao.getAll();
      final entities = configs.map(_toEntity).toList();
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
      return rd.Success(_toEntity(config));
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar configuração: $e'),
      );
    }
  }

  @override
  Future<rd.Result<SqlServerConfig>> create(SqlServerConfig config) async {
    try {
      final companion = _toCompanion(config);
      await _database.sqlServerConfigDao.insertConfig(companion);
      // Retorna a config original (não criptografada) para uso imediato
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
      final companion = _toCompanion(config);
      await _database.sqlServerConfigDao.updateConfig(companion);
      // Retorna a config original (não criptografada) para uso imediato
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
      final entities = configs.map(_toEntity).toList();
      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar configurações ativas: $e'),
      );
    }
  }

  SqlServerConfig _toEntity(SqlServerConfigsTableData data) {
    final decryptedPassword = EncryptionService.decrypt(data.password);

    return SqlServerConfig(
      id: data.id,
      name: data.name,
      server: data.server,
      database: data.database,
      username: data.username,
      password: decryptedPassword,
      port: data.port,
      enabled: data.enabled,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  SqlServerConfigsTableCompanion _toCompanion(SqlServerConfig config) {
    final encryptedPassword = EncryptionService.encrypt(config.password);

    return SqlServerConfigsTableCompanion(
      id: Value(config.id),
      name: Value(config.name),
      server: Value(config.server),
      database: Value(config.database),
      username: Value(config.username),
      password: Value(encryptedPassword),
      port: Value(config.port),
      enabled: Value(config.enabled),
      createdAt: Value(config.createdAt),
      updatedAt: Value(config.updatedAt),
    );
  }
}
