import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:result_dart/result_dart.dart';

abstract class IDatabaseBackupPort<T extends DatabaseConnectionConfig> {
  Future<Result<BackupExecutionResult>> executeBackup({
    required T config,
    required BackupExecutionContext context,
  });

  Future<Result<bool>> testConnection(T config);

  Future<Result<int>> getDatabaseSizeBytes({
    required T config,
    Duration? timeout,
  });
}
