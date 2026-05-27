import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_firebird_config_repository.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_serializers.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_store.dart';

/// Implementacao concreta de [DatabaseConfigStore] que despacha por
/// `databaseType` para os repositorios de config (Sybase, SqlServer,
/// Postgres, Firebird). Reusa `DatabaseConfigSerializers` para Map<->Entity.
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
    required this.firebirdRepository,
  });

  final ISybaseConfigRepository sybaseRepository;
  final ISqlServerConfigRepository sqlServerRepository;
  final IPostgresConfigRepository postgresRepository;
  final IFirebirdConfigRepository firebirdRepository;

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
        case RemoteDatabaseType.firebird:
          final r = await firebirdRepository.getAll();
          if (r.isError()) {
            return _failureFromException(r.exceptionOrNull());
          }
          final cfgs = r.getOrNull() ?? const [];
          return DatabaseConfigOutcome.success(
            configs: cfgs
                .map(DatabaseConfigSerializers.firebirdToMap)
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
        case RemoteDatabaseType.firebird:
          final cfg = DatabaseConfigSerializers.firebirdFromMap(config);
          final r = await firebirdRepository.create(cfg);
          if (r.isError()) return _failureFromException(r.exceptionOrNull());
          final created = r.getOrNull();
          if (created == null) {
            return DatabaseConfigOutcome.failure(
              error: 'Repository retornou null sem erro',
              errorCode: ErrorCode.unknown,
            );
          }
          return DatabaseConfigOutcome.success(
            config: DatabaseConfigSerializers.firebirdToMap(created),
          );
      }
      // ignore: avoid_catching_errors -- ArgumentError do serializer (payload remoto).
    } on ArgumentError catch (e) {
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
      // Segredos (password, cryptKey) NAO sao reenviados pelo servidor
      // ao cliente nos snapshots de list/get; se o cliente apenas
      // re-submeter o formulario sem reescrever a senha, o payload
      // chega com string vazia. Sem o merge abaixo, o repository
      // sobrescrevia o segredo armazenado com vazio (perda silenciosa).
      // Politica: campo ausente OU string vazia -> manter valor atual.
      final merged = await _mergeSecretsWithExisting(type, config);
      switch (type) {
        case RemoteDatabaseType.sybase:
          final cfg = DatabaseConfigSerializers.sybaseFromMap(merged);
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
          final cfg = DatabaseConfigSerializers.sqlServerFromMap(merged);
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
          final cfg = DatabaseConfigSerializers.postgresFromMap(merged);
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
        case RemoteDatabaseType.firebird:
          final cfg = DatabaseConfigSerializers.firebirdFromMap(merged);
          final r = await firebirdRepository.update(cfg);
          if (r.isError()) return _failureFromException(r.exceptionOrNull());
          final updated = r.getOrNull();
          if (updated == null) {
            return DatabaseConfigOutcome.failure(
              error: 'Repository retornou null sem erro',
              errorCode: ErrorCode.unknown,
            );
          }
          return DatabaseConfigOutcome.success(
            config: DatabaseConfigSerializers.firebirdToMap(updated),
          );
      }
      // ignore: avoid_catching_errors -- ArgumentError do serializer (payload remoto).
    } on ArgumentError catch (e) {
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

  /// Le a entidade existente e injeta os segredos ausentes no payload
  /// remoto. Mantem o resto do payload intacto (host, porta, opcoes,
  /// ...) — apenas preenche `password`/`cryptKey` quando vierem vazios.
  ///
  /// Implementacao via **tabela de extractors** (1 entrada por SGBD): o
  /// extractor recebe o `id` e devolve os pares `{ campo → valor }` que
  /// estao armazenados no servidor. So sao injectados no payload quando
  /// o campo correspondente vier ausente ou vazio.
  ///
  /// Optimizacao: se nenhum dos campos sensiveis do tipo vier vazio,
  /// **nao chamamos `getById`** (evita I/O contra repository quando o
  /// cliente reenviou todos os segredos).
  ///
  /// Se `id` nao existir no payload ou a config nao existir mais no
  /// servidor, devolve o payload inalterado (o repository.update vai
  /// devolver `NotFound` adiante).
  Future<Map<String, dynamic>> _mergeSecretsWithExisting(
    RemoteDatabaseType type,
    Map<String, dynamic> payload,
  ) async {
    final id = payload['id'] is String ? payload['id'] as String : '';
    if (id.isEmpty) return payload;
    final descriptor = _secretDescriptors[type];
    if (descriptor == null) return payload;
    final missingKeys = descriptor.sensitiveKeys
        .where((k) => !_hasNonEmptyString(payload, k))
        .toList(growable: false);
    if (missingKeys.isEmpty) return payload;
    final merged = Map<String, dynamic>.from(payload);

    try {
      final stored = await descriptor.extractor(this, id);
      for (final key in missingKeys) {
        final value = stored[key];
        if (value == null || value.isEmpty) continue;
        merged[key] = value;
      }
    } on Object catch (e, st) {
      LoggerService.warning(
        'Falha ao mesclar segredos existentes (${type.wireName}): $e',
        e,
        st,
      );
    }
    return merged;
  }

  /// Descritor por SGBD: lista de chaves sensiveis no payload + extractor
  /// que devolve os pares `{ campo → valor }` armazenados no servidor.
  /// Adicionar SGBD novo = uma entrada nesta tabela (sem mexer no
  /// dispatcher do `update`).
  static final Map<RemoteDatabaseType, _SecretDescriptor>
  _secretDescriptors = {
    RemoteDatabaseType.sybase: _SecretDescriptor(
      sensitiveKeys: const ['password'],
      extractor: (store, id) async {
        final cfg = (await store.sybaseRepository.getById(id)).getOrNull();
        if (cfg == null) return const {};
        return {'password': cfg.password};
      },
    ),
    RemoteDatabaseType.sqlServer: _SecretDescriptor(
      sensitiveKeys: const ['password'],
      extractor: (store, id) async {
        final cfg = (await store.sqlServerRepository.getById(id)).getOrNull();
        if (cfg == null) return const {};
        return {'password': cfg.password};
      },
    ),
    RemoteDatabaseType.postgres: _SecretDescriptor(
      sensitiveKeys: const ['password'],
      extractor: (store, id) async {
        final cfg = (await store.postgresRepository.getById(id)).getOrNull();
        if (cfg == null) return const {};
        return {'password': cfg.password};
      },
    ),
    RemoteDatabaseType.firebird: _SecretDescriptor(
      sensitiveKeys: const ['password', 'cryptKey'],
      extractor: (store, id) async {
        final cfg = (await store.firebirdRepository.getById(id)).getOrNull();
        if (cfg == null) return const {};
        return {'password': cfg.password, 'cryptKey': cfg.cryptKey};
      },
    ),
  };

  static bool _hasNonEmptyString(Map<String, dynamic> map, String key) {
    final v = map[key];
    return v is String && v.isNotEmpty;
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
        case RemoteDatabaseType.firebird:
          final r = await firebirdRepository.delete(configId);
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

  /// Classifica exception do repository em ErrorCode publico.
  DatabaseConfigOutcome _failureFromException(Object? exception) {
    if (exception == null) {
      return DatabaseConfigOutcome.failure(
        error: 'Erro desconhecido no repository',
        errorCode: ErrorCode.unknown,
      );
    }
    if (exception is Failure) {
      final errorCode = switch (exception) {
        NotFoundFailure() => ErrorCode.fileNotFound,
        ValidationFailure() => ErrorCode.invalidRequest,
        _ => ErrorCode.unknown,
      };
      final message = exception.message;
      return DatabaseConfigOutcome.failure(
        error: message.isEmpty ? exception.toString() : message,
        errorCode: errorCode,
      );
    }
    final msg = exception.toString();
    final lower = msg.toLowerCase();
    final notFound =
        lower.contains('not found') ||
        lower.contains('nao encontrad') ||
        lower.contains('não encontrad') ||
        lower.contains('inexistente');
    return DatabaseConfigOutcome.failure(
      error: msg,
      errorCode: notFound ? ErrorCode.fileNotFound : ErrorCode.unknown,
    );
  }
}

/// Metadata por SGBD para o merge de segredos vazios em
/// `RealDatabaseConfigStore._mergeSecretsWithExisting`.
///
/// Mantido como tipo dedicado (em vez de `Record`/`Tuple`) para deixar
/// claro o contrato e permitir extensao futura (ex.: regras de
/// validacao adicionais por chave) sem mexer no dispatcher de update.
class _SecretDescriptor {
  const _SecretDescriptor({
    required this.sensitiveKeys,
    required this.extractor,
  });

  /// Chaves do payload remoto consideradas sensiveis para este SGBD.
  /// Apenas estas sao verificadas antes de chamar o `extractor`
  /// (otimizacao: se o cliente reenviou todas, evitamos I/O).
  final List<String> sensitiveKeys;

  /// Resolve a entidade armazenada e devolve os pares
  /// `{ chave_sensivel → valor }` que devem ser usados quando o
  /// payload nao reenviar o valor.
  final Future<Map<String, String>> Function(
    RealDatabaseConfigStore store,
    String id,
  )
  extractor;
}
