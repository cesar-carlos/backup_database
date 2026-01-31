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
  });

  Future<Result<bool>> testConnection(PostgresConfig config);

  Future<Result<List<String>>> listDatabases({
    required PostgresConfig config,
    Duration? timeout,
  });
}
