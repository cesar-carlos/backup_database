import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';

/// Agendamento de backup específico para SQL Server com opções avançadas de performance.
/// Estende [Schedule] adicionando opções específicas do SQL Server.
class SqlServerBackupSchedule extends Schedule {
  SqlServerBackupSchedule({
    required super.name,
    required super.databaseConfigId,
    required super.databaseType,
    required super.scheduleType,
    required super.scheduleConfig,
    required super.destinationIds,
    required super.backupFolder,
    super.backupType,
    super.truncateLog,
    super.compressBackup,
    super.compressionFormat,
    super.enabled,
    super.enableChecksum,
    super.verifyAfterBackup,
    super.verifyPolicy,
    super.postBackupScript,
    super.lastRunAt,
    super.nextRunAt,
    super.id,
    super.createdAt,
    super.updatedAt,
    super.backupTimeout,
    super.verifyTimeout,
    super.isConvertedDifferential,
    this.sqlServerBackupOptions = const SqlServerBackupOptions(),
  });

  final SqlServerBackupOptions sqlServerBackupOptions;

  @override
  SqlServerBackupSchedule copyWith({
    String? id,
    String? name,
    String? databaseConfigId,
    DatabaseType? databaseType,
    String? scheduleType,
    String? scheduleConfig,
    List<String>? destinationIds,
    String? backupFolder,
    BackupType? backupType,
    bool? truncateLog,
    bool? compressBackup,
    CompressionFormat? compressionFormat,
    bool? enabled,
    bool? enableChecksum,
    bool? verifyAfterBackup,
    VerifyPolicy? verifyPolicy,
    String? postBackupScript,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    Duration? backupTimeout,
    Duration? verifyTimeout,
    SqlServerBackupOptions? sqlServerBackupOptions,
    bool? isConvertedDifferential,
  }) {
    final baseSchedule = super.copyWith(
      id: id,
      name: name,
      databaseConfigId: databaseConfigId,
      databaseType: databaseType,
      scheduleType: scheduleType,
      scheduleConfig: scheduleConfig,
      destinationIds: destinationIds,
      backupFolder: backupFolder,
      backupType: backupType,
      truncateLog: truncateLog,
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
      updatedAt: updatedAt,
      backupTimeout: backupTimeout,
      verifyTimeout: verifyTimeout,
      isConvertedDifferential: isConvertedDifferential,
    );

    return SqlServerBackupSchedule(
      name: baseSchedule.name,
      databaseConfigId: baseSchedule.databaseConfigId,
      databaseType: baseSchedule.databaseType,
      scheduleType: baseSchedule.scheduleType,
      scheduleConfig: baseSchedule.scheduleConfig,
      destinationIds: baseSchedule.destinationIds,
      backupFolder: baseSchedule.backupFolder,
      backupType: baseSchedule.backupType,
      truncateLog: baseSchedule.truncateLog,
      compressBackup: baseSchedule.compressBackup,
      compressionFormat: baseSchedule.compressionFormat,
      enabled: baseSchedule.enabled,
      enableChecksum: baseSchedule.enableChecksum,
      verifyAfterBackup: baseSchedule.verifyAfterBackup,
      verifyPolicy: baseSchedule.verifyPolicy,
      postBackupScript: baseSchedule.postBackupScript,
      lastRunAt: baseSchedule.lastRunAt,
      nextRunAt: baseSchedule.nextRunAt,
      id: baseSchedule.id,
      createdAt: baseSchedule.createdAt,
      updatedAt: baseSchedule.updatedAt,
      backupTimeout: baseSchedule.backupTimeout,
      verifyTimeout: baseSchedule.verifyTimeout,
      sqlServerBackupOptions:
          sqlServerBackupOptions ?? this.sqlServerBackupOptions,
    );
  }
}
