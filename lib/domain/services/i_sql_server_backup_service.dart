import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:result_dart/result_dart.dart';

abstract class ISqlServerBackupService {
  Future<Result<BackupExecutionResult>> executeBackup({
    required SqlServerConfig config,
    required String outputDirectory,
    required String scheduleId,
    BackupType backupType,
    String? customFileName,
    bool truncateLog,
    bool enableChecksum,
    bool verifyAfterBackup,
    VerifyPolicy verifyPolicy,
    SqlServerBackupOptions? sqlServerBackupOptions,
    Duration? backupTimeout,
    Duration? verifyTimeout,
    String? cancelTag,
  });

  Future<Result<bool>> testConnection(SqlServerConfig config);

  Future<Result<List<String>>> listDatabases({
    required SqlServerConfig config,
    Duration? timeout,
  });

  Future<Result<List<String>>> listBackupFiles({
    required SqlServerConfig config,
    Duration? timeout,
  });

  /// Tamanho aproximado em bytes do banco em [config] (soma de
  /// `sys.master_files`). Usado para validar espaço livre antes do backup.
  Future<Result<int>> getDatabaseSizeBytes({
    required SqlServerConfig config,
    Duration? timeout,
  });
}
