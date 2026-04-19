import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';

/// Resultado opaco de uma operacao de CRUD em database config.
/// Sucesso carrega `config` (Map opaco) ou `configs` (lista) quando
/// aplicavel; falha carrega `error` + `errorCode`.
class DatabaseConfigOutcome {
  const DatabaseConfigOutcome({
    required this.success,
    this.config,
    this.configs,
    this.error,
    this.errorCode,
  });

  factory DatabaseConfigOutcome.success({
    Map<String, dynamic>? config,
    List<Map<String, dynamic>>? configs,
  }) =>
      DatabaseConfigOutcome(
        success: true,
        config: config,
        configs: configs,
      );

  factory DatabaseConfigOutcome.failure({
    required String error,
    required ErrorCode errorCode,
  }) =>
      DatabaseConfigOutcome(
        success: false,
        error: error,
        errorCode: errorCode,
      );

  final bool success;
  final Map<String, dynamic>? config;
  final List<Map<String, dynamic>>? configs;
  final String? error;
  final ErrorCode? errorCode;
}

/// Abstracao de CRUD de configuracoes de banco de dados.
///
/// Mantem o handler de socket totalmente desacoplado dos repositorios
/// concretos (Sybase / SqlServer / Postgres). Em producao, uma
/// implementacao real despachara por `databaseType` para o
/// repository correto. Em testes leves, basta um mock que captura
/// as chamadas.
///
/// Os Maps sao **opacos** no protocolo — cada implementacao concreta
/// sabe converter entre Map e a entity tipada (`SybaseConfig`,
/// `SqlServerConfig`, `PostgresConfig`). Mantem o protocolo neutro
/// em relacao a evolucoes de schema das entities.
abstract class DatabaseConfigStore {
  Future<DatabaseConfigOutcome> list(RemoteDatabaseType type);
  Future<DatabaseConfigOutcome> create(
    RemoteDatabaseType type,
    Map<String, dynamic> config,
  );
  Future<DatabaseConfigOutcome> update(
    RemoteDatabaseType type,
    Map<String, dynamic> config,
  );
  Future<DatabaseConfigOutcome> delete(
    RemoteDatabaseType type,
    String configId,
  );
}

/// Implementacao default usada em ambientes minimos (testes leves,
/// servidor recem-inicializado sem DI cabeado). Toda operacao
/// retorna falha indicando falta de wiring. Cliente recebe
/// errorCode `UNKNOWN` com mensagem clara.
class NotConfiguredDatabaseConfigStore implements DatabaseConfigStore {
  const NotConfiguredDatabaseConfigStore();

  static DatabaseConfigOutcome _notConfigured(String op) =>
      DatabaseConfigOutcome.failure(
        error: 'CRUD de database config nao configurado para esta operacao: $op',
        errorCode: ErrorCode.unknown,
      );

  @override
  Future<DatabaseConfigOutcome> list(RemoteDatabaseType type) async =>
      _notConfigured('list ${type.wireName}');

  @override
  Future<DatabaseConfigOutcome> create(
    RemoteDatabaseType type,
    Map<String, dynamic> config,
  ) async =>
      _notConfigured('create ${type.wireName}');

  @override
  Future<DatabaseConfigOutcome> update(
    RemoteDatabaseType type,
    Map<String, dynamic> config,
  ) async =>
      _notConfigured('update ${type.wireName}');

  @override
  Future<DatabaseConfigOutcome> delete(
    RemoteDatabaseType type,
    String configId,
  ) async =>
      _notConfigured('delete ${type.wireName}');
}
