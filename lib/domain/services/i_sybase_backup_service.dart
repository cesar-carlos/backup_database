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
  });

  Future<Result<bool>> testConnection(SybaseConfig config);
}
