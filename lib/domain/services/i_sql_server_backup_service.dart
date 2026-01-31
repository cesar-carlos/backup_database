import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:result_dart/result_dart.dart';

abstract class ISqlServerBackupService {
  Future<Result<BackupExecutionResult>> executeBackup({
    required SqlServerConfig config,
    required String outputDirectory,
    BackupType backupType,
    String? customFileName,
    bool truncateLog,
    bool enableChecksum,
    bool verifyAfterBackup,
  });

  Future<Result<bool>> testConnection(SqlServerConfig config);

  Future<Result<List<String>>> listDatabases({
    required SqlServerConfig config,
    Duration? timeout,
  });
}
