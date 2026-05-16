import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';

class BackupExecutionContext {
  BackupExecutionContext({
    required this.outputDirectory,
    required this.scheduleId,
    this.backupType = BackupType.full,
    this.customFileName,
    this.truncateLog = true,
    this.enableChecksum = false,
    this.verifyAfterBackup = false,
    this.verifyPolicy = VerifyPolicy.bestEffort,
    this.sqlServerBackupOptions,
    this.backupTimeout,
    this.verifyTimeout,
    this.cancelTag,
    this.pgBasebackupPath,
    this.dbbackupPath,
    this.sybaseBackupOptions,
  });

  final String outputDirectory;
  final String scheduleId;
  final BackupType backupType;
  final String? customFileName;
  final bool truncateLog;
  final bool enableChecksum;
  final bool verifyAfterBackup;
  final VerifyPolicy verifyPolicy;
  final SqlServerBackupOptions? sqlServerBackupOptions;
  final Duration? backupTimeout;
  final Duration? verifyTimeout;
  final String? cancelTag;
  final String? pgBasebackupPath;
  final String? dbbackupPath;
  final SybaseBackupOptions? sybaseBackupOptions;
}
