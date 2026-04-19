import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
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

  /// Template SQL compartilhado pelos `SELECT *` (com ou sem WHERE).
  /// Antes era duplicado linha-a-linha em `getAll`/`getById`/`getEnabled`,
  /// triplicando manutenção quando uma coluna era adicionada.
  static const String _selectColumns = '''
        SELECT
          id, name, server_name,
          COALESCE(database_name, server_name) as database_name,
          COALESCE(database_file, '') as database_file,
          COALESCE(port, 2638) as port,
          username, password,
          COALESCE(enabled, 1) as enabled,
          COALESCE(is_replication_environment, 0) as is_replication_environment,
          created_at, updated_at
        FROM sybase_configs_table''';

  @override
  Future<rd.Result<List<SybaseConfig>>> getAll() {
    return _selectMany(
      whereClause: null,
      whereVariables: const [],
      errorContext: 'configurações',
      missingTableContext: 'sybase_configs',
    );
  }

  @override
  Future<rd.Result<List<SybaseConfig>>> getEnabled() {
    return _selectMany(
      whereClause: 'WHERE enabled = 1',
      whereVariables: const [],
      errorContext: 'configurações ativas',
      missingTableContext: 'sybase_configs',
    );
  }

  @override
  Future<rd.Result<SybaseConfig>> getById(String id) async {
    if (!await _tableExists()) {
      LoggerService.warning(
        'Tabela sybase_configs_table não existe ao buscar por ID: $id',
      );
      return const rd.Failure(
        NotFoundFailure(
          message: 'Configuração Sybase não encontrada (tabela não existe)',
        ),
      );
    }

    LoggerService.debug('Buscando configuração Sybase por ID: $id');

    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar configuração',
      action: () async {
        final row = await _database
            .customSelect(
              '$_selectColumns WHERE id = ?',
              readsFrom: {_database.sybaseConfigsTable},
              variables: [Variable<String>(id)],
            )
            .getSingleOrNull();

        if (row == null) {
          LoggerService.warning(
            'Configuração Sybase não encontrada para ID: $id',
          );
          throw NotFoundFailure(
            message: 'Configuração Sybase não encontrada para ID: $id',
          );
        }

        LoggerService.debug(
          'Configuração Sybase encontrada: ${row.read<String>('name')}',
        );
        return _toEntityFromRow(row);
      },
    );
  }

  @override
  Future<rd.Result<SybaseConfig>> create(SybaseConfig config) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao criar configuração',
      action: () async {
        await _storePasswordOrThrow(config.id, config.password);

        await _database.customStatement(
          '''
          INSERT INTO sybase_configs_table (
            id, name, server_name, database_name, database_file, port,
            username, password, enabled, is_replication_environment,
            created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            if (config.isReplicationEnvironment) 1 else 0,
            config.createdAt.millisecondsSinceEpoch,
            config.updatedAt.millisecondsSinceEpoch,
          ],
        );

        return config;
      },
    );
  }

  @override
  Future<rd.Result<SybaseConfig>> update(SybaseConfig config) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao atualizar configuração',
      action: () async {
        await _storePasswordOrThrow(config.id, config.password);

        await _database.customStatement(
          '''
          UPDATE sybase_configs_table SET
            name = ?, server_name = ?, database_name = ?, database_file = ?,
            port = ?, username = ?, password = ?, enabled = ?,
            is_replication_environment = ?, updated_at = ?
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
            if (config.isReplicationEnvironment) 1 else 0,
            DateTime.now().millisecondsSinceEpoch,
            config.id,
          ],
        );

        return config;
      },
    );
  }

  @override
  Future<rd.Result<void>> delete(String id) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao deletar configuração',
      action: () async {
        LoggerService.info('Deletando configuração Sybase: $id');

        final passwordKey = '$_passwordKeyPrefix$id';
        await _secureCredentialService.deletePassword(key: passwordKey);

        await _database.customStatement(
          'DELETE FROM sybase_configs_table WHERE id = ?',
          [id],
        );

        LoggerService.info('Configuração Sybase deletada com sucesso: $id');
      },
    );
  }

  Future<bool> _tableExists() async {
    try {
      final result = await _database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='sybase_configs_table'",
          )
          .getSingleOrNull();
      return result != null;
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao verificar se tabela sybase_configs_table existe: $e',
      );
      return false;
    }
  }

  /// Centraliza a lógica de "selecionar muitos com fallback de tabela
  /// inexistente". Antes era replicada quase idêntica em `getAll` e
  /// `getEnabled` (~30 linhas cada).
  Future<rd.Result<List<SybaseConfig>>> _selectMany({
    required String? whereClause,
    required List<Variable> whereVariables,
    required String errorContext,
    required String missingTableContext,
  }) async {
    if (!await _tableExists()) {
      LoggerService.warning(
        'Tabela sybase_configs_table não existe, retornando lista vazia',
      );
      return const rd.Success(<SybaseConfig>[]);
    }

    try {
      final query = whereClause == null
          ? _selectColumns
          : '$_selectColumns $whereClause';
      final rows = await _database
          .customSelect(
            query,
            readsFrom: {_database.sybaseConfigsTable},
            variables: whereVariables,
          )
          .get();

      final entities = <SybaseConfig>[];
      for (final row in rows) {
        try {
          final entity = await _toEntityFromRow(row);
          entities.add(entity);
        } on Object catch (e, stackTrace) {
          // Skip-on-error semantics preservada: uma row corrompida não
          // deve impedir o resto da lista. Antes era duplicada em
          // `getAll` e `getEnabled`.
          final id = row.read<String>('id');
          LoggerService.error(
            'Erro ao converter configuração Sybase ($errorContext): $id',
            e,
            stackTrace,
          );
          continue;
        }
      }

      return rd.Success(entities);
    } on Object catch (e, stackTrace) {
      // Race condition: a tabela passou no `_tableExists` mas foi removida
      // antes do SELECT (raro, mas possível em scripts de migração).
      // Tratamos como lista vazia em vez de erro.
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('no such table') ||
          errorStr.contains(missingTableContext)) {
        LoggerService.warning(
          'Tabela sybase_configs não encontrada durante SELECT, '
          'retornando lista vazia',
        );
        return const rd.Success(<SybaseConfig>[]);
      }

      LoggerService.error(
        'Erro ao buscar $errorContext Sybase',
        e,
        stackTrace,
      );
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao buscar $errorContext: $e',
          originalError: e,
        ),
      );
    }
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

  Future<SybaseConfig> _toEntityFromRow(QueryRow row) async {
    final id = row.read<String>('id');
    final name = row.read<String>('name');
    final serverName = row.read<String>('server_name');
    final databaseName = row.read<String>('database_name');
    final databaseFile = row.read<String>('database_file');
    final port = row.read<int>('port');
    final username = row.read<String>('username');
    final enabledInt = row.read<int>('enabled');
    final isReplicationInt = row.read<int>('is_replication_environment');
    final createdAtInt = row.read<int>('created_at');
    final updatedAtInt = row.read<int>('updated_at');

    final enabled = enabledInt == 1;
    final isReplicationEnvironment = isReplicationInt == 1;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtInt);
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtInt);

    final passwordKey = '$_passwordKeyPrefix$id';
    final passwordResult = await _secureCredentialService.getPassword(
      key: passwordKey,
    );

    final password = passwordResult.getOrElse((_) => '');

    final effectiveDatabaseName = databaseName.isNotEmpty
        ? databaseName
        : serverName;

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
      isReplicationEnvironment: isReplicationEnvironment,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

}
