import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

part 'schedule.freezed.dart';

enum ScheduleType { daily, weekly, monthly, interval }

enum DatabaseType { sqlServer, sybase, postgresql, firebird }

extension ScheduleTypeExtension on ScheduleType {
  String toValue() {
    switch (this) {
      case ScheduleType.daily:
        return 'daily';
      case ScheduleType.weekly:
        return 'weekly';
      case ScheduleType.monthly:
        return 'monthly';
      case ScheduleType.interval:
        return 'interval';
    }
  }
}

ScheduleType scheduleTypeFromString(String value) {
  switch (value) {
    case 'daily':
      return ScheduleType.daily;
    case 'weekly':
      return ScheduleType.weekly;
    case 'monthly':
      return ScheduleType.monthly;
    case 'interval':
      return ScheduleType.interval;
    default:
      return ScheduleType.daily;
  }
}

@freezed
abstract class Schedule with _$Schedule {
  const Schedule._();

  factory Schedule({
    required String name,
    required String databaseConfigId,
    required DatabaseType databaseType,
    required String scheduleType,
    required String scheduleConfig,
    required List<String> destinationIds,
    required String backupFolder,
    String? id,
    BackupType backupType = BackupType.full,
    bool truncateLog = true,
    bool compressBackup = true,
    CompressionFormat? compressionFormat,
    bool enabled = true,
    bool enableChecksum = false,
    bool verifyAfterBackup = false,
    VerifyPolicy verifyPolicy = VerifyPolicy.bestEffort,
    String? postBackupScript,
    Duration backupTimeout = const Duration(hours: 2),
    Duration verifyTimeout = const Duration(minutes: 30),
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool isConvertedDifferential = false,
    int? firebirdNbackupPhysicalLevel,
    SqlServerBackupOptions? sqlServerBackupOptions,
    SybaseBackupOptions? sybaseBackupOptions,
  }) {
    return Schedule.raw(
      id: id ?? const Uuid().v4(),
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
      compressionFormat: compressionFormat ?? CompressionFormat.none,
      enabled: enabled,
      enableChecksum: enableChecksum,
      verifyAfterBackup: verifyAfterBackup,
      verifyPolicy: verifyPolicy,
      postBackupScript: postBackupScript,
      backupTimeout: backupTimeout,
      verifyTimeout: verifyTimeout,
      lastRunAt: lastRunAt,
      nextRunAt: nextRunAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isConvertedDifferential: isConvertedDifferential,
      firebirdNbackupPhysicalLevel: firebirdNbackupPhysicalLevel,
      sqlServerBackupOptions: sqlServerBackupOptions,
      sybaseBackupOptions: sybaseBackupOptions,
    );
  }

  const factory Schedule.raw({
    required String id,
    required String name,
    required String databaseConfigId,
    required DatabaseType databaseType,
    required String scheduleType,
    required String scheduleConfig,
    required List<String> destinationIds,
    required String backupFolder,
    required CompressionFormat compressionFormat,
    @Default(BackupType.full) BackupType backupType,
    @Default(true) bool truncateLog,
    @Default(true) bool compressBackup,
    @Default(true) bool enabled,
    @Default(false) bool enableChecksum,
    @Default(false) bool verifyAfterBackup,
    @Default(VerifyPolicy.bestEffort) VerifyPolicy verifyPolicy,
    String? postBackupScript,
    @Default(Duration(hours: 2)) Duration backupTimeout,
    @Default(Duration(minutes: 30)) Duration verifyTimeout,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    @Default(false) bool isConvertedDifferential,
    int? firebirdNbackupPhysicalLevel,
    SqlServerBackupOptions? sqlServerBackupOptions,
    SybaseBackupOptions? sybaseBackupOptions,
  }) = _Schedule;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Schedule && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

extension ScheduleEngineOptions on Schedule {
  SqlServerBackupOptions get resolvedSqlServerBackupOptions =>
      sqlServerBackupOptions ?? const SqlServerBackupOptions();

  SybaseBackupOptions get resolvedSybaseBackupOptions =>
      sybaseBackupOptions ?? SybaseBackupOptions.safeDefaults;
}
