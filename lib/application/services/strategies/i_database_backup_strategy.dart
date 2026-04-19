import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:result_dart/result_dart.dart';

/// Estratégia de execução de backup específica para um SGBD.
///
/// O `BackupOrchestratorService` delega para a implementação certa via
/// um `Map<DatabaseType, IDatabaseBackupStrategy>`. Adicionar suporte a
/// um novo SGBD passa a ser apenas registrar uma nova estratégia em DI,
/// sem precisar modificar o orchestrator (Open/Closed).
///
/// Cada estratégia é responsável por:
///  - validações específicas do SGBD (ex.: preflight de log Sybase,
///    rejeição de differential em Sybase, recovery model do SQL Server);
///  - extrair opções específicas do `Schedule` (cast para os subtipos);
///  - chamar o serviço de infraestrutura correspondente;
///  - opcionalmente enriquecer `BackupExecutionResult.metrics` com dados
///    específicos do SGBD (ex.: `baseFullId` da cadeia Sybase).
abstract class IDatabaseBackupStrategy {
  /// Tipo de banco que esta estratégia atende.
  DatabaseType get databaseType;

  /// Executa o backup para [schedule] usando a config previamente carregada
  /// em [databaseConfig] (cast pelo orchestrator). [outputDirectory] já
  /// inclui a subpasta do tipo de backup. [cancelTag] é a tag canônica
  /// para cancelamento via `IBackupCancellationService`.
  Future<Result<BackupExecutionResult>> execute({
    required Schedule schedule,
    required Object databaseConfig,
    required String outputDirectory,
    required BackupType backupType,
    required String cancelTag,
  });
}
