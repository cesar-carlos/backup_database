import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_serializers.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_store.dart';

/// Implementacao concreta de [DatabaseConfigStore] que despacha por
/// `databaseType` para os 3 repositories existentes (Sybase, SqlServer,
/// Postgres). Reusa `DatabaseConfigSerializers` para Map<->Entity.
///
/// Comportamento de erro:
/// - `Result.isError()` -> outcome.failure com errorCode classificado
///   (notFound se mensagem indica "nao encontrado"; unknown caso
///   contrario)
/// - payload ad-hoc invalido (campo faltando) -> errorCode.invalidRequest
///
/// **Decisao de seguranca**: respostas de listagem/get NAO incluem
/// password (controlado por `includePassword: false` no serializer).
/// Mantem o segredo persistido apenas no servidor.
class RealDatabaseConfigStore implements DatabaseConfigStore {
  RealDatabaseConfigStore({
    required this.sybaseRepository,
    required this.sqlServerRepository,
    required this.postgresRepository,
  });

  final ISybaseConfigRepository sybaseRepository;
  final ISqlServerConfigRepository sqlServerRepository;
  final IPostgresConfigRepository postgresRepository;

  @override
  Future<DatabaseConfigOutcome> list(RemoteDatabaseType type) async {
    try {
      switch (type) {
        case RemoteDatabaseType.sybase:
          final r = await sybaseRepository.getAll();
          if (r.isError()) {
            return _failureFromException(r.exceptionOrNull());
          }
          final cfgs = r.getOrNull() ?? const [];
          return DatabaseConfigOutcome.success(
            configs: cfgs
                .map(DatabaseConfigSerializers.sybaseToMap)
                .toList(growable: false),
          );
        case RemoteDatabaseType.sqlServer:
          final r = await sqlServerRepository.getAll();
          if (r.isError()) {
            return _failureFromException(r.exceptionOrNull());
          }
          final cfgs = r.getOrNull() ?? const [];
          return DatabaseConfigOutcome.success(
            configs: cfgs
                .map(DatabaseConfigSerializers.sqlServerToMap)
                .toList(growable: false),
          );
        case RemoteDatabaseType.postgres:
          final r = await postgresRepository.getAll();
          if (r.isError()) {
            return _failureFromException(r.exceptionOrNull());
          }
          final cfgs = r.getOrNull() ?? const [];
          return DatabaseConfigOutcome.success(
            configs: cfgs
                .map(DatabaseConfigSerializers.postgresToMap)
                .toList(growable: false),
          );
      }
    } on Object catch (e, st) {
      LoggerService.warning(
        'RealDatabaseConfigStore.list ${type.wireName}: $e',
        e,
        st,
      );
      return DatabaseConfigOutcome.failure(
        error: 'Erro inesperado: $e',
        errorCode: ErrorCode.unknown,
      );
    }
  }

  @override
  Future<DatabaseConfigOutcome> create(
    RemoteDatabaseType type,
    Map<String, dynamic> config,
  ) async {
    try {
      switch (type) {
        case RemoteDatabaseType.sybase:
          final cfg = DatabaseConfigSerializers.sybaseFromMap(config);
          final r = await sybaseRepository.create(cfg);
          if (r.isError()) return _failureFromException(r.exceptionOrNull());
          final created = r.getOrNull();
          if (created == null) {
            return DatabaseConfigOutcome.failure(
              error: 'Repository retornou null sem erro',
              errorCode: ErrorCode.unknown,
            );
          }
          return DatabaseConfigOutcome.success(
            config: DatabaseConfigSerializers.sybaseToMap(created),
          );
        case RemoteDatabaseType.sqlServer:
          final cfg = DatabaseConfigSerializers.sqlServerFromMap(config);
          final r = await sqlServerRepository.create(cfg);
          if (r.isError()) return _failureFromException(r.exceptionOrNull());
          final created = r.getOrNull();
          if (created == null) {
            return DatabaseConfigOutcome.failure(
              error: 'Repository retornou null sem erro',
              errorCode: ErrorCode.unknown,
            );
          }
          return DatabaseConfigOutcome.success(
            config: DatabaseConfigSerializers.sqlServerToMap(created),
          );
        case RemoteDatabaseType.postgres:
          final cfg = DatabaseConfigSerializers.postgresFromMap(config);
          final r = await postgresRepository.create(cfg);
          if (r.isError()) return _failureFromException(r.exceptionOrNull());
          final created = r.getOrNull();
          if (created == null) {
            return DatabaseConfigOutcome.failure(
              error: 'Repository retornou null sem erro',
              errorCode: ErrorCode.unknown,
            );
          }
          return DatabaseConfigOutcome.success(
            config: DatabaseConfigSerializers.postgresToMap(created),
          );
      }
    }
    // ignore: avoid_catching_errors — ArgumentError sinaliza payload
    // malformado do cliente, nao bug do servidor.
    on ArgumentError catch (e) {
      return DatabaseConfigOutcome.failure(
        error: 'Payload de config invalido: $e',
        errorCode: ErrorCode.invalidRequest,
      );
    } on Object catch (e, st) {
      LoggerService.warning(
        'RealDatabaseConfigStore.create ${type.wireName}: $e',
        e,
        st,
      );
      return DatabaseConfigOutcome.failure(
        error: 'Erro inesperado: $e',
        errorCode: ErrorCode.unknown,
      );
    }
  }

  @override
  Future<DatabaseConfigOutcome> update(
    RemoteDatabaseType type,
    Map<String, dynamic> config,
  ) async {
    try {
      switch (type) {
        case RemoteDatabaseType.sybase:
          final cfg = DatabaseConfigSerializers.sybaseFromMap(config);
          final r = await sybaseRepository.update(cfg);
          if (r.isError()) return _failureFromException(r.exceptionOrNull());
          final updated = r.getOrNull();
          if (updated == null) {
            return DatabaseConfigOutcome.failure(
              error: 'Repository retornou null sem erro',
              errorCode: ErrorCode.unknown,
            );
          }
          return DatabaseConfigOutcome.success(
            config: DatabaseConfigSerializers.sybaseToMap(updated),
          );
        case RemoteDatabaseType.sqlServer:
          final cfg = DatabaseConfigSerializers.sqlServerFromMap(config);
          final r = await sqlServerRepository.update(cfg);
          if (r.isError()) return _failureFromException(r.exceptionOrNull());
          final updated = r.getOrNull();
          if (updated == null) {
            return DatabaseConfigOutcome.failure(
              error: 'Repository retornou null sem erro',
              errorCode: ErrorCode.unknown,
            );
          }
          return DatabaseConfigOutcome.success(
            config: DatabaseConfigSerializers.sqlServerToMap(updated),
          );
        case RemoteDatabaseType.postgres:
          final cfg = DatabaseConfigSerializers.postgresFromMap(config);
          final r = await postgresRepository.update(cfg);
          if (r.isError()) return _failureFromException(r.exceptionOrNull());
          final updated = r.getOrNull();
          if (updated == null) {
            return DatabaseConfigOutcome.failure(
              error: 'Repository retornou null sem erro',
              errorCode: ErrorCode.unknown,
            );
          }
          return DatabaseConfigOutcome.success(
            config: DatabaseConfigSerializers.postgresToMap(updated),
          );
      }
    }
    // ignore: avoid_catching_errors — ArgumentError sinaliza payload
    // malformado do cliente, nao bug do servidor.
    on ArgumentError catch (e) {
      return DatabaseConfigOutcome.failure(
        error: 'Payload de config invalido: $e',
        errorCode: ErrorCode.invalidRequest,
      );
    } on Object catch (e, st) {
      LoggerService.warning(
        'RealDatabaseConfigStore.update ${type.wireName}: $e',
        e,
        st,
      );
      return DatabaseConfigOutcome.failure(
        error: 'Erro inesperado: $e',
        errorCode: ErrorCode.unknown,
      );
    }
  }

  @override
  Future<DatabaseConfigOutcome> delete(
    RemoteDatabaseType type,
    String configId,
  ) async {
    try {
      switch (type) {
        case RemoteDatabaseType.sybase:
          final r = await sybaseRepository.delete(configId);
          if (r.isError()) return _failureFromException(r.exceptionOrNull());
          return DatabaseConfigOutcome.success();
        case RemoteDatabaseType.sqlServer:
          final r = await sqlServerRepository.delete(configId);
          if (r.isError()) return _failureFromException(r.exceptionOrNull());
          return DatabaseConfigOutcome.success();
        case RemoteDatabaseType.postgres:
          final r = await postgresRepository.delete(configId);
          if (r.isError()) return _failureFromException(r.exceptionOrNull());
          return DatabaseConfigOutcome.success();
      }
    } on Object catch (e, st) {
      LoggerService.warning(
        'RealDatabaseConfigStore.delete ${type.wireName}: $e',
        e,
        st,
      );
      return DatabaseConfigOutcome.failure(
        error: 'Erro inesperado: $e',
        errorCode: ErrorCode.unknown,
      );
    }
  }

  /// Classifica exception do repository em ErrorCode publico. Mensagens
  /// que contenham "nao encontrado" / "not found" mapeiam para
  /// fileNotFound; demais para unknown.
  DatabaseConfigOutcome _failureFromException(Object? exception) {
    if (exception == null) {
      return DatabaseConfigOutcome.failure(
        error: 'Erro desconhecido no repository',
        errorCode: ErrorCode.unknown,
      );
    }
    final msg = exception.toString();
    final lower = msg.toLowerCase();
    final notFound = lower.contains('not found') ||
        lower.contains('nao encontrad') ||
        lower.contains('inexistente');
    return DatabaseConfigOutcome.failure(
      error: msg,
      errorCode: notFound ? ErrorCode.fileNotFound : ErrorCode.unknown,
    );
  }
}
