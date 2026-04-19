import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:result_dart/result_dart.dart';

abstract class IPostgresBackupService {
  Future<Result<BackupExecutionResult>> executeBackup({
    required PostgresConfig config,
    required String outputDirectory,
    BackupType backupType,
    String? customFileName,
    bool verifyAfterBackup,
    String? pgBasebackupPath,
    Duration? backupTimeout,
    Duration? verifyTimeout,
    String? cancelTag,
  });

  Future<Result<bool>> testConnection(PostgresConfig config);

  Future<Result<List<String>>> listDatabases({
    required PostgresConfig config,
    Duration? timeout,
  });

  /// Tamanho aproximado em bytes do banco indicado em [config]. Usado pelo
  /// orchestrator para validar espaço livre suficiente no destino antes de
  /// iniciar o backup. Retorna falha se a consulta não puder ser feita; o
  /// orchestrator deve tratar como "tamanho desconhecido" e cair no
  /// mínimo configurável.
  Future<Result<int>> getDatabaseSizeBytes({
    required PostgresConfig config,
    Duration? timeout,
  });
}
