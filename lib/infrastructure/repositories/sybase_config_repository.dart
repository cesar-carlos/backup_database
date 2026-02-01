import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SybaseConfigRepository implements ISybaseConfigRepository {
  SybaseConfigRepository(
    this._database,
    this._secureCredentialService,
  );

  final AppDatabase _database;
  final ISecureCredentialService _secureCredentialService;

  static const String _passwordKeyPrefix = 'sybase_password_';

  @override
  Future<rd.Result<List<SybaseConfig>>> getAll() async {
    try {
      if (!await _tableExists()) {
        LoggerService.warning(
          'Tabela sybase_configs não existe, retornando lista vazia',
        );
        return const rd.Success(<SybaseConfig>[]);
      }

      final rows = await _database
          .customSelect(
            '''
        SELECT 
          id, name, server_name, 
          COALESCE(database_name, server_name) as database_name,
          COALESCE(database_file, '') as database_file,
          COALESCE(port, 2638) as port,
          username, password, 
          COALESCE(enabled, 1) as enabled,
          created_at, updated_at
        FROM sybase_configs
        ''',
            readsFrom: {_database.sybaseConfigsTable},
          )
          .get();

      final entities = <SybaseConfig>[];
      for (final row in rows) {
        try {
          final entity = await _toEntityFromRow(row);
          entities.add(entity);
        } on Object catch (e, stackTrace) {
          final id = row.read<String>('id');
          LoggerService.error(
            'Erro ao converter configuração Sybase: $id',
            e,
            stackTrace,
          );

          continue;
        }
      }

      return rd.Success(entities);
    } on Object catch (e, stackTrace) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('no such table') ||
          errorStr.contains('sybase_configs')) {
        LoggerService.warning(
          'Tabela sybase_configs não encontrada, retornando lista vazia',
        );
        return const rd.Success(<SybaseConfig>[]);
      }

      LoggerService.error('Erro ao buscar configurações Sybase', e, stackTrace);
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao buscar configurações: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<bool> _tableExists() async {
    try {
      final result = await _database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='sybase_configs'",
          )
          .getSingleOrNull();
      return result != null;
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao verificar se tabela sybase_configs existe: $e',
      );
      return false;
    }
  }

  @override
  Future<rd.Result<SybaseConfig>> getById(String id) async {
    try {
      if (!await _tableExists()) {
        LoggerService.warning(
          'Tabela sybase_configs não existe ao buscar por ID: $id',
        );
        return const rd.Failure(
          NotFoundFailure(
            message: 'Configuração Sybase não encontrada (tabela não existe)',
          ),
        );
      }

      LoggerService.debug('Buscando configuração Sybase por ID: $id');

      final row = await _database
          .customSelect(
            '''
        SELECT 
          id, name, server_name, 
          COALESCE(database_name, server_name) as database_name,
          COALESCE(database_file, '') as database_file,
          COALESCE(port, 2638) as port,
          username, password, 
          COALESCE(enabled, 1) as enabled,
          created_at, updated_at
        FROM sybase_configs
        WHERE id = ?
        ''',
            readsFrom: {_database.sybaseConfigsTable},
            variables: [Variable<String>(id)],
          )
          .getSingleOrNull();

      if (row == null) {
        LoggerService.warning(
          'Configuração Sybase não encontrada para ID: $id',
        );
        return rd.Failure(
          NotFoundFailure(
            message: 'Configuração Sybase não encontrada para ID: $id',
          ),
        );
      }

      LoggerService.debug(
        'Configuração Sybase encontrada: ${row.read<String>('name')}',
      );

      try {
        final entity = await _toEntityFromRow(row);
        return rd.Success(entity);
      } on Object catch (e, stackTrace) {
        LoggerService.error(
          'Erro ao converter configuração Sybase: $id',
          e,
          stackTrace,
        );
        return rd.Failure(
          DatabaseFailure(
            message: 'Erro ao processar configuração: $e',
            originalError: e,
          ),
        );
      }
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao buscar configuração Sybase: $id',
        e,
        stackTrace,
      );
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao buscar configuração: $e',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<SybaseConfig>> create(SybaseConfig config) async {
    try {
      final passwordKey = '$_passwordKeyPrefix${config.id}';
      final storeResult = await _secureCredentialService.storePassword(
        key: passwordKey,
        password: config.password,
      );

      if (storeResult.isError()) {
        return rd.Failure(storeResult.exceptionOrNull()!);
      }

      await _database.customStatement(
        '''
        INSERT INTO sybase_configs (
          id, name, server_name, database_name, database_file, port,
          username, password, enabled, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          config.id,
          config.name,
          config.serverName,
          config.databaseNameValue,
          config.databaseFile,
          config.portValue,
          config.username,
          '',
          if (config.enabled) 1 else 0,
          config.createdAt.millisecondsSinceEpoch,
          config.updatedAt.millisecondsSinceEpoch,
        ],
      );

      return rd.Success(config);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao criar configuração Sybase', e, stackTrace);
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao criar configuração: $e',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<SybaseConfig>> update(SybaseConfig config) async {
    try {
      final passwordKey = '$_passwordKeyPrefix${config.id}';
      final storeResult = await _secureCredentialService.storePassword(
        key: passwordKey,
        password: config.password,
      );

      if (storeResult.isError()) {
        return rd.Failure(storeResult.exceptionOrNull()!);
      }

      await _database.customStatement(
        '''
        UPDATE sybase_configs SET
          name = ?, server_name = ?, database_name = ?, database_file = ?,
          port = ?, username = ?, password = ?, enabled = ?, updated_at = ?
        WHERE id = ?
        ''',
        [
          config.name,
          config.serverName,
          config.databaseNameValue,
          config.databaseFile,
          config.portValue,
          config.username,
          '',
          if (config.enabled) 1 else 0,
          DateTime.now().millisecondsSinceEpoch,
          config.id,
        ],
      );

      return rd.Success(config);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao atualizar configuração Sybase',
        e,
        stackTrace,
      );
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao atualizar configuração: $e',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<void>> delete(String id) async {
    try {
      LoggerService.info('Deletando configuração Sybase: $id');

      final passwordKey = '$_passwordKeyPrefix$id';
      await _secureCredentialService.deletePassword(key: passwordKey);

      await _database.customStatement(
        'DELETE FROM sybase_configs WHERE id = ?',
        [id],
      );

      LoggerService.info('Configuração Sybase deletada com sucesso: $id');
      return const rd.Success(unit);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao deletar configuração Sybase: $id',
        e,
        stackTrace,
      );
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao deletar configuração: $e',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<List<SybaseConfig>>> getEnabled() async {
    try {
      if (!await _tableExists()) {
        return const rd.Success(<SybaseConfig>[]);
      }

      final rows = await _database
          .customSelect(
            '''
        SELECT 
          id, name, server_name, 
          COALESCE(database_name, server_name) as database_name,
          COALESCE(database_file, '') as database_file,
          COALESCE(port, 2638) as port,
          username, password, 
          COALESCE(enabled, 1) as enabled,
          created_at, updated_at
        FROM sybase_configs
        WHERE enabled = 1
        ''',
            readsFrom: {_database.sybaseConfigsTable},
          )
          .get();

      final entities = <SybaseConfig>[];
      for (final row in rows) {
        try {
          final entity = await _toEntityFromRow(row);
          entities.add(entity);
        } on Object catch (e, stackTrace) {
          final id = row.read<String>('id');
          LoggerService.error(
            'Erro ao converter configuração Sybase ativa: $id',
            e,
            stackTrace,
          );

          continue;
        }
      }

      return rd.Success(entities);
    } on Object catch (e, stackTrace) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('no such table') ||
          errorStr.contains('sybase_configs')) {
        return const rd.Success(<SybaseConfig>[]);
      }

      LoggerService.error(
        'Erro ao buscar configurações Sybase ativas',
        e,
        stackTrace,
      );
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao buscar configurações ativas: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<SybaseConfig> _toEntityFromRow(QueryRow row) async {
    final id = row.read<String>('id');
    final name = row.read<String>('name');
    final serverName = row.read<String>('server_name');
    final databaseName = row.read<String>('database_name');
    final databaseFile = row.read<String>('database_file');
    final port = row.read<int>('port');
    final username = row.read<String>('username');
    final enabledInt = row.read<int>('enabled');
    final createdAtInt = row.read<int>('created_at');
    final updatedAtInt = row.read<int>('updated_at');

    final enabled = enabledInt == 1;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtInt);
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtInt);

    final passwordKey = '$_passwordKeyPrefix$id';
    final passwordResult = await _secureCredentialService.getPassword(
      key: passwordKey,
    );

    final password = passwordResult.getOrElse((_) => '');

    final effectiveDatabaseName =
        databaseName.isNotEmpty ? databaseName : serverName;

    return SybaseConfig(
      id: id,
      name: name,
      serverName: serverName,
      databaseName: DatabaseName(effectiveDatabaseName),
      databaseFile: databaseFile,
      port: PortNumber(port),
      username: username,
      password: password,
      enabled: enabled,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
