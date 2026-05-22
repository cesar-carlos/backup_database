import 'package:backup_database/core/constants/secure_credential_keys.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/repositories/base_database_config_repository.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SybaseConfigRepository
    extends BaseDatabaseConfigRepository<SybaseConfig, QueryRow>
    implements ISybaseConfigRepository {
  SybaseConfigRepository(
    super.database,
    super.secureCredentialService,
  );

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
      whereVariables: const <Variable>[],
      errorContext: 'configurações',
      missingTableContext: 'sybase_configs',
    );
  }

  @override
  Future<rd.Result<List<SybaseConfig>>> getEnabled() {
    return _selectMany(
      whereClause: 'WHERE enabled = 1',
      whereVariables: const <Variable>[],
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
        final row = await database
            .customSelect(
              '$_selectColumns WHERE id = ?',
              readsFrom: {database.sybaseConfigsTable},
              variables: <Variable>[Variable<String>(id)],
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
        return rowToEntity(row);
      },
    );
  }

  @override
  String credentialKeyFor(String configId) =>
      SecureCredentialKeys.sybasePasswordKey(configId);

  @override
  Future<List<QueryRow>> fetchAllRows() async => <QueryRow>[];

  @override
  Future<List<QueryRow>> fetchEnabledRows() async => <QueryRow>[];

  @override
  Future<QueryRow?> fetchRowById(String id) async => null;

  @override
  Future<void> writeInsert(SybaseConfig config) {
    return database.customStatement(
      '''
          INSERT INTO sybase_configs_table (
            id, name, server_name, database_name, database_file, port,
            username, password, enabled, is_replication_environment,
            created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
      <Object?>[
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
  }

  @override
  Future<void> writeUpdate(SybaseConfig config) {
    return database.customStatement(
      '''
          UPDATE sybase_configs_table SET
            name = ?, server_name = ?, database_name = ?, database_file = ?,
            port = ?, username = ?, password = ?, enabled = ?,
            is_replication_environment = ?, updated_at = ?
          WHERE id = ?
          ''',
      <Object?>[
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
  }

  @override
  Future<void> onBeforeDelete(String id) async {
    LoggerService.info('Deletando configuração Sybase: $id');
  }

  @override
  Future<void> writeDelete(String id) async {
    await database.customStatement(
      'DELETE FROM sybase_configs_table WHERE id = ?',
      <Object?>[id],
    );
    LoggerService.info('Configuração Sybase deletada com sucesso: $id');
  }

  Future<bool> _tableExists() async {
    try {
      final result = await database
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

    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar $errorContext Sybase',
      action: () async {
        try {
          final query = whereClause == null
              ? _selectColumns
              : '$_selectColumns $whereClause';
          final rows = await database
              .customSelect(
                query,
                readsFrom: {database.sybaseConfigsTable},
                variables: whereVariables,
              )
              .get();

          final entities = <SybaseConfig>[];
          for (final row in rows) {
            try {
              final entity = await rowToEntity(row);
              entities.add(entity);
            } on Object catch (e, stackTrace) {
              final rowId = row.read<String>('id');
              LoggerService.error(
                'Erro ao converter configuração Sybase ($errorContext): $rowId',
                e,
                stackTrace,
              );
            }
          }

          return entities;
        } on Object catch (e) {
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('no such table') ||
              errorStr.contains(missingTableContext)) {
            LoggerService.warning(
              'Tabela sybase_configs não encontrada durante SELECT, '
              'retornando lista vazia',
            );
            return <SybaseConfig>[];
          }
          rethrow;
        }
      },
    );
  }

  @override
  Future<SybaseConfig> rowToEntity(QueryRow row) async {
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

    final password = await credentials.readPasswordOrEmpty(
      credentialKeyFor(id),
    );

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
