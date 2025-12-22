import 'package:result_dart/result_dart.dart';

import '../entities/sql_server_config.dart';
import '../entities/backup_type.dart';
import 'backup_execution_result.dart';

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

