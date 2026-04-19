import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:result_dart/result_dart.dart';

abstract class ISybaseBackupService {
  Future<Result<BackupExecutionResult>> executeBackup({
    required SybaseConfig config,
    required String outputDirectory,
    BackupType backupType,
    String? customFileName,
    String? dbbackupPath,
    bool truncateLog,
    bool verifyAfterBackup,
    VerifyPolicy verifyPolicy = VerifyPolicy.bestEffort,
    Duration? backupTimeout,
    Duration? verifyTimeout,
    SybaseBackupOptions? sybaseBackupOptions,
    String? cancelTag,
  });

  Future<Result<bool>> testConnection(SybaseConfig config);

  /// Tamanho aproximado em bytes do banco SQL Anywhere em [config]
  /// (soma de `db_property('FileSize')` para o database file). Best-effort:
  /// se o servidor não permitir consulta, retorna falha e o orchestrator
  /// trata como "desconhecido".
  Future<Result<int>> getDatabaseSizeBytes({
    required SybaseConfig config,
    Duration? timeout,
  });
}
