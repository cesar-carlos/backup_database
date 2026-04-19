import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_serializers.dart';
import 'package:backup_database/infrastructure/socket/server/database_connection_prober.dart';

/// Implementacao concreta de [DatabaseConnectionProber] que despacha
/// por tipo de banco para o backup service correspondente.
///
/// **Reusa a infraestrutura existente**: cada `*BackupService.testConnection`
/// ja faz a sondagem real (process spawn + comando de probe).
/// Aqui apenas fazemos:
/// 1. Resolver a config (por id persistido OU por map ad-hoc).
/// 2. Chamar `testConnection` e medir latencia.
/// 3. Mapear `Result<bool>` para [DatabaseProbeOutcome] com errorCode
///    apropriado.
///
/// Mapeamento de erros:
/// - sondagem retorna `Success(true)`  -> outcome.success
/// - sondagem retorna `Success(false)` -> outcome.failure (auth)
/// - sondagem retorna `Failure(...)`   -> outcome.failure (io/timeout
///   conforme tipo da exception, fallback `unknown`)
/// - config nao encontrada (id invalido) -> errorCode.fileNotFound
/// - payload ad-hoc invalido            -> errorCode.invalidRequest
class RealDatabaseConnectionProber implements DatabaseConnectionProber {
  RealDatabaseConnectionProber({
    required this.sybaseService,
    required this.sqlServerService,
    required this.postgresService,
    required this.sybaseRepository,
    required this.sqlServerRepository,
    required this.postgresRepository,
    Stopwatch Function()? stopwatchFactory,
  }) : _stopwatchFactory = stopwatchFactory ?? Stopwatch.new;

  final ISybaseBackupService sybaseService;
  final ISqlServerBackupService sqlServerService;
  final IPostgresBackupService postgresService;
  final ISybaseConfigRepository sybaseRepository;
  final ISqlServerConfigRepository sqlServerRepository;
  final IPostgresConfigRepository postgresRepository;
  final Stopwatch Function() _stopwatchFactory;

  @override
  Future<DatabaseProbeOutcome> probe({
    required RemoteDatabaseType databaseType,
    required DatabaseConfigRef configRef,
    Duration? timeout,
  }) async {
    final stopwatch = _stopwatchFactory()..start();
    try {
      switch (databaseType) {
        case RemoteDatabaseType.sybase:
          return await _probeSybase(configRef, stopwatch);
        case RemoteDatabaseType.sqlServer:
          return await _probeSqlServer(configRef, stopwatch);
        case RemoteDatabaseType.postgres:
          return await _probePostgres(configRef, stopwatch);
      }
    } on Object catch (e, st) {
      // Defesa final: qualquer excecao nao prevista vira failure
      // unknown — handler ja faz fail-closed mas duplicar aqui
      // garante medicao de latencia mesmo em path de erro inesperado.
      LoggerService.warning(
        'RealDatabaseConnectionProber: unexpected error: $e',
        e,
        st,
      );
      stopwatch.stop();
      return DatabaseProbeOutcome.failure(
        latencyMs: stopwatch.elapsedMilliseconds,
        error: 'Erro inesperado: $e',
        errorCode: ErrorCode.unknown,
      );
    }
  }

  Future<DatabaseProbeOutcome> _probeSybase(
    DatabaseConfigRef ref,
    Stopwatch sw,
  ) async {
    switch (ref) {
      case DatabaseConfigById(id: final id):
        final cfgResult = await sybaseRepository.getById(id);
        final cfg = cfgResult.getOrNull();
        if (cfgResult.isError() || cfg == null) {
          sw.stop();
          return DatabaseProbeOutcome.failure(
            latencyMs: sw.elapsedMilliseconds,
            error: 'Config Sybase nao encontrada: $id',
            errorCode: ErrorCode.fileNotFound,
          );
        }
        final result = await sybaseService.testConnection(cfg);
        sw.stop();
        return _mapBoolResult(result, sw);
      case DatabaseConfigAdhoc(config: final map):
        try {
          final cfg = DatabaseConfigSerializers.sybaseFromMap(map);
          final result = await sybaseService.testConnection(cfg);
          sw.stop();
          return _mapBoolResult(result, sw);
        }
        // ignore: avoid_catching_errors -- ArgumentError do serializer (map ad-hoc remoto).
        on ArgumentError catch (e) {
          sw.stop();
          return DatabaseProbeOutcome.failure(
            latencyMs: sw.elapsedMilliseconds,
            error: 'Config ad-hoc invalida: $e',
            errorCode: ErrorCode.invalidRequest,
          );
        }
    }
  }

  Future<DatabaseProbeOutcome> _probeSqlServer(
    DatabaseConfigRef ref,
    Stopwatch sw,
  ) async {
    switch (ref) {
      case DatabaseConfigById(id: final id):
        final cfgResult = await sqlServerRepository.getById(id);
        final cfg = cfgResult.getOrNull();
        if (cfgResult.isError() || cfg == null) {
          sw.stop();
          return DatabaseProbeOutcome.failure(
            latencyMs: sw.elapsedMilliseconds,
            error: 'Config SqlServer nao encontrada: $id',
            errorCode: ErrorCode.fileNotFound,
          );
        }
        final result = await sqlServerService.testConnection(cfg);
        sw.stop();
        return _mapBoolResult(result, sw);
      case DatabaseConfigAdhoc(config: final map):
        try {
          final cfg = DatabaseConfigSerializers.sqlServerFromMap(map);
          final result = await sqlServerService.testConnection(cfg);
          sw.stop();
          return _mapBoolResult(result, sw);
        }
        // ignore: avoid_catching_errors -- ArgumentError do serializer (map ad-hoc remoto).
        on ArgumentError catch (e) {
          sw.stop();
          return DatabaseProbeOutcome.failure(
            latencyMs: sw.elapsedMilliseconds,
            error: 'Config ad-hoc invalida: $e',
            errorCode: ErrorCode.invalidRequest,
          );
        }
    }
  }

  Future<DatabaseProbeOutcome> _probePostgres(
    DatabaseConfigRef ref,
    Stopwatch sw,
  ) async {
    switch (ref) {
      case DatabaseConfigById(id: final id):
        final cfgResult = await postgresRepository.getById(id);
        final cfg = cfgResult.getOrNull();
        if (cfgResult.isError() || cfg == null) {
          sw.stop();
          return DatabaseProbeOutcome.failure(
            latencyMs: sw.elapsedMilliseconds,
            error: 'Config Postgres nao encontrada: $id',
            errorCode: ErrorCode.fileNotFound,
          );
        }
        final result = await postgresService.testConnection(cfg);
        sw.stop();
        return _mapBoolResult(result, sw);
      case DatabaseConfigAdhoc(config: final map):
        try {
          final cfg = DatabaseConfigSerializers.postgresFromMap(map);
          final result = await postgresService.testConnection(cfg);
          sw.stop();
          return _mapBoolResult(result, sw);
        }
        // ignore: avoid_catching_errors -- ArgumentError do serializer (map ad-hoc remoto).
        on ArgumentError catch (e) {
          sw.stop();
          return DatabaseProbeOutcome.failure(
            latencyMs: sw.elapsedMilliseconds,
            error: 'Config ad-hoc invalida: $e',
            errorCode: ErrorCode.invalidRequest,
          );
        }
    }
  }

  /// Mapeia o `Result<bool>` retornado por `testConnection` para um
  /// outcome do prober. `true` = success; `false` = falha de auth (o
  /// service ja interpretou o codigo do banco e retornou bool); falha
  /// do Result = erro de transporte/timeout.
  DatabaseProbeOutcome _mapBoolResult(
    dynamic result,
    Stopwatch sw,
  ) {
    // result e Result<bool, dynamic> — usamos pattern matching estatico
    // via toString fallback porque o tipo e generico.
    try {
      final dynamic r = result;
      final isError = r.isError() as bool;
      if (isError) {
        final exception = r.exceptionOrNull() as Object?;
        return DatabaseProbeOutcome.failure(
          latencyMs: sw.elapsedMilliseconds,
          error: exception?.toString() ?? 'Erro desconhecido na sondagem',
          errorCode: _classifyError(exception),
        );
      }
      final connected = r.getOrNull() as bool?;
      if (connected ?? false) {
        return DatabaseProbeOutcome.success(
          latencyMs: sw.elapsedMilliseconds,
        );
      }
      return DatabaseProbeOutcome.failure(
        latencyMs: sw.elapsedMilliseconds,
        error: 'Conexao recusada (autenticacao ou indisponibilidade)',
        errorCode: ErrorCode.authenticationFailed,
      );
    } on Object catch (e, st) {
      LoggerService.warning(
        'RealDatabaseConnectionProber: erro ao interpretar Result: $e',
        e,
        st,
      );
      return DatabaseProbeOutcome.failure(
        latencyMs: sw.elapsedMilliseconds,
        error: 'Erro inesperado: $e',
        errorCode: ErrorCode.unknown,
      );
    }
  }

  /// Classifica a exception em ErrorCode de protocolo. Heuristica
  /// baseada no toString — defensivo, fallback `unknown`. Em iteracao
  /// futura podemos enriquecer com tipos exception especificos do
  /// driver (ex.: SocketException -> ioError).
  ErrorCode _classifyError(Object? exception) {
    if (exception == null) return ErrorCode.unknown;
    final msg = exception.toString().toLowerCase();
    if (msg.contains('timeout') || msg.contains('expirou')) {
      return ErrorCode.timeout;
    }
    if (msg.contains('auth') ||
        msg.contains('senha') ||
        msg.contains('login') ||
        msg.contains('credencial')) {
      return ErrorCode.authenticationFailed;
    }
    if (msg.contains('socket') || msg.contains('connection')) {
      return ErrorCode.ioError;
    }
    return ErrorCode.unknown;
  }
}
