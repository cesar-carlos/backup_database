import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';

/// Resultado opaco de uma sondagem de conexao com banco de dados.
/// Representado como `record`-like (POJO) para facilitar serializacao
/// no handler e nao depender de `Result` nas fronteiras de socket.
class DatabaseProbeOutcome {
  const DatabaseProbeOutcome({
    required this.connected,
    required this.latencyMs,
    this.error,
    this.errorCode,
    this.details,
  });

  factory DatabaseProbeOutcome.success({
    required int latencyMs,
    Map<String, dynamic>? details,
  }) {
    return DatabaseProbeOutcome(
      connected: true,
      latencyMs: latencyMs,
      details: details,
    );
  }

  factory DatabaseProbeOutcome.failure({
    required int latencyMs,
    required String error,
    required ErrorCode errorCode,
    Map<String, dynamic>? details,
  }) {
    return DatabaseProbeOutcome(
      connected: false,
      latencyMs: latencyMs,
      error: error,
      errorCode: errorCode,
      details: details,
    );
  }

  final bool connected;
  final int latencyMs;
  final String? error;
  final ErrorCode? errorCode;
  final Map<String, dynamic>? details;
}

/// Referencia para a config a ser sondada. Implementada como
/// algebraic-data-type-like para forcar o handler a tratar os dois
/// modos (id persistido vs ad-hoc) explicitamente. Padrao mantem
/// possivel adicionar futuros modos (ex.: connection string raw).
sealed class DatabaseConfigRef {
  const DatabaseConfigRef();
}

class DatabaseConfigById extends DatabaseConfigRef {
  const DatabaseConfigById(this.id);
  final String id;
}

class DatabaseConfigAdhoc extends DatabaseConfigRef {
  const DatabaseConfigAdhoc(this.config);
  final Map<String, dynamic> config;
}

/// Sonda conexao com um banco. Implementacoes concretas sao injetadas
/// via DI (por tipo de banco) — handler nao conhece detalhes de cada
/// driver. Em testes, fica trivial mockar com um stub que retorna
/// outcomes deterministicos.
abstract class DatabaseConnectionProber {
  Future<DatabaseProbeOutcome> probe({
    required RemoteDatabaseType databaseType,
    required DatabaseConfigRef configRef,
    Duration? timeout,
  });
}

/// Implementacao default para uso em ambientes minimos (ex.: testes
/// que so querem validar o roteamento). Sempre retorna `failure` com
/// codigo `unknown` — handler responde mas indica que sondagem real
/// nao esta cabeada. Em producao, substitua via DI por implementacao
/// real (ver `RealDatabaseConnectionProber` em PR-2 final).
class NotConfiguredProber implements DatabaseConnectionProber {
  const NotConfiguredProber();

  @override
  Future<DatabaseProbeOutcome> probe({
    required RemoteDatabaseType databaseType,
    required DatabaseConfigRef configRef,
    Duration? timeout,
  }) async {
    return DatabaseProbeOutcome.failure(
      latencyMs: 0,
      error:
          'Sondagem nao configurada para ${databaseType.wireName}: '
          'servidor sem prober cabeado',
      errorCode: ErrorCode.unknown,
    );
  }
}
