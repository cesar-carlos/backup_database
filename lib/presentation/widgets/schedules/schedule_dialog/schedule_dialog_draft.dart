import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';

class ScheduleDialogDraft {
  const ScheduleDialogDraft({
    required this.name,
    required this.databaseConfigId,
    required this.databaseType,
    required this.scheduleTypeString,
    required this.scheduleConfigJson,
    required this.destinationIds,
    required this.backupFolder,
    required this.backupType,
    required this.compressBackup,
    required this.compressionFormat,
    required this.enabled,
    required this.enableChecksum,
    required this.verifyAfterBackup,
    required this.verifyPolicy,
    required this.truncateLog,
    required this.backupTimeout,
    required this.verifyTimeout,
    this.id,
    this.postBackupScript,
    this.lastRunAt,
    this.nextRunAt,
    this.createdAt,
    this.sqlServerBackupOptions,
    this.sybaseBackupOptions,
    this.firebirdNbackupPhysicalLevel,
    this.isConvertedDifferential,
  });

  final String? id;
  final String name;
  final String databaseConfigId;
  final DatabaseType databaseType;
  final String scheduleTypeString;
  final String scheduleConfigJson;
  final List<String> destinationIds;
  final String backupFolder;
  final BackupType backupType;
  final bool compressBackup;
  final CompressionFormat compressionFormat;
  final bool enabled;
  final bool enableChecksum;
  final bool verifyAfterBackup;
  final VerifyPolicy verifyPolicy;
  final String? postBackupScript;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final DateTime? createdAt;
  final bool truncateLog;
  final Duration backupTimeout;
  final Duration verifyTimeout;
  final SqlServerBackupOptions? sqlServerBackupOptions;
  final SybaseBackupOptions? sybaseBackupOptions;
  final int? firebirdNbackupPhysicalLevel;
  final bool? isConvertedDifferential;

  Schedule toSchedule() {
    if (databaseType == DatabaseType.sqlServer) {
      return Schedule(
        id: id,
        name: name,
        databaseConfigId: databaseConfigId,
        databaseType: databaseType,
        scheduleType: scheduleTypeString,
        scheduleConfig: scheduleConfigJson,
        destinationIds: destinationIds,
        backupFolder: backupFolder,
        backupType: backupType,
        compressBackup: compressBackup,
        compressionFormat: compressionFormat,
        enabled: enabled,
        enableChecksum: enableChecksum,
        verifyAfterBackup: verifyAfterBackup,
        verifyPolicy: verifyPolicy,
        postBackupScript: postBackupScript,
        lastRunAt: lastRunAt,
        nextRunAt: nextRunAt,
        createdAt: createdAt,
        truncateLog: truncateLog,
        backupTimeout: backupTimeout,
        verifyTimeout: verifyTimeout,
        sqlServerBackupOptions: sqlServerBackupOptions,
        isConvertedDifferential: isConvertedDifferential ?? false,
      );
    } else if (databaseType == DatabaseType.sybase) {
      final effectiveLogMode =
          sybaseBackupOptions?.logBackupMode ??
          (truncateLog
              ? SybaseLogBackupMode.truncate
              : SybaseLogBackupMode.only);
      final resolvedSybaseOptions = SybaseBackupOptions(
        checkpointLog: sybaseBackupOptions?.checkpointLog,
        serverSide: sybaseBackupOptions?.serverSide ?? false,
        autoTuneWriters: sybaseBackupOptions?.autoTuneWriters ?? false,
        blockSize: sybaseBackupOptions?.blockSize,
        logBackupMode: effectiveLogMode,
      );
      return Schedule(
        id: id,
        name: name,
        databaseConfigId: databaseConfigId,
        databaseType: databaseType,
        scheduleType: scheduleTypeString,
        scheduleConfig: scheduleConfigJson,
        destinationIds: destinationIds,
        backupFolder: backupFolder,
        backupType: backupType,
        compressBackup: compressBackup,
        compressionFormat: compressionFormat,
        enabled: enabled,
        enableChecksum: enableChecksum,
        verifyAfterBackup: verifyAfterBackup,
        verifyPolicy: verifyPolicy,
        postBackupScript: postBackupScript,
        lastRunAt: lastRunAt,
        nextRunAt: nextRunAt,
        createdAt: createdAt,
        truncateLog: effectiveLogMode == SybaseLogBackupMode.truncate,
        backupTimeout: backupTimeout,
        verifyTimeout: verifyTimeout,
        sybaseBackupOptions: resolvedSybaseOptions,
        isConvertedDifferential:
            isConvertedDifferential ?? (backupType == BackupType.differential),
      );
    } else {
      return Schedule(
        id: id,
        name: name,
        databaseConfigId: databaseConfigId,
        databaseType: databaseType,
        scheduleType: scheduleTypeString,
        scheduleConfig: scheduleConfigJson,
        destinationIds: destinationIds,
        backupFolder: backupFolder,
        backupType: backupType,
        compressBackup: compressBackup,
        compressionFormat: compressionFormat,
        enabled: enabled,
        enableChecksum: enableChecksum,
        verifyAfterBackup: verifyAfterBackup,
        verifyPolicy: verifyPolicy,
        postBackupScript: postBackupScript,
        lastRunAt: lastRunAt,
        nextRunAt: nextRunAt,
        createdAt: createdAt,
        truncateLog: truncateLog,
        backupTimeout: backupTimeout,
        verifyTimeout: verifyTimeout,
        firebirdNbackupPhysicalLevel: firebirdNbackupPhysicalLevel,
      );
    }
  }
}
