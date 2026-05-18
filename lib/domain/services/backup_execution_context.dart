import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'backup_execution_context.freezed.dart';

@freezed
abstract class BackupExecutionContext with _$BackupExecutionContext {
  const factory BackupExecutionContext({
    required String outputDirectory,
    required String scheduleId,
    @Default(BackupType.full) BackupType backupType,
    String? customFileName,
    @Default(true) bool truncateLog,
    @Default(false) bool enableChecksum,
    @Default(false) bool verifyAfterBackup,
    @Default(VerifyPolicy.bestEffort) VerifyPolicy verifyPolicy,
    SqlServerBackupOptions? sqlServerBackupOptions,
    Duration? backupTimeout,
    Duration? verifyTimeout,
    String? cancelTag,
    String? pgBasebackupPath,
    String? dbbackupPath,
    SybaseBackupOptions? sybaseBackupOptions,
    int? firebirdNbackupPhysicalLevel,
  }) = _BackupExecutionContext;
}
