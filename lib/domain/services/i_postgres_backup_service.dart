import 'package:result_dart/result_dart.dart';

import '../entities/postgres_config.dart';
import '../entities/backup_type.dart';
import 'backup_execution_result.dart';

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

