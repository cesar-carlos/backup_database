import 'package:result_dart/result_dart.dart';

import '../entities/backup_type.dart';
import '../entities/sybase_config.dart';
import 'backup_execution_result.dart';

abstract class ISybaseBackupService {
  Future<Result<BackupExecutionResult>> executeBackup({
    required SybaseConfig config,
    required String outputDirectory,
    BackupType backupType,
    String? customFileName,
    String? dbbackupPath,
    bool truncateLog,
    bool verifyAfterBackup,
  });

  Future<Result<bool>> testConnection(SybaseConfig config);
}

