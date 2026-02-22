import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:uuid/uuid.dart';

enum ScheduleType { daily, weekly, monthly, interval }

enum DatabaseType { sqlServer, sybase, postgresql }

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

class Schedule {
  Schedule({
    required this.name,
    required this.databaseConfigId,
    required this.databaseType,
    required this.scheduleType,
    required this.scheduleConfig,
    required this.destinationIds,
    required this.backupFolder,
    String? id,
    this.backupType = BackupType.full,
    this.truncateLog = true,
    this.compressBackup = true,
    CompressionFormat? compressionFormat,
    this.enabled = true,
    this.enableChecksum = false,
    this.verifyAfterBackup = false,
    this.verifyPolicy = VerifyPolicy.bestEffort,
    this.postBackupScript,
    this.backupTimeout = const Duration(hours: 2),
    this.verifyTimeout = const Duration(minutes: 30),
    this.lastRunAt,
    this.nextRunAt,
    this.createdAt,
    this.updatedAt,
    this.isConvertedDifferential = false,
  }) : id = id ?? const Uuid().v4(),
       compressionFormat = compressionFormat ?? CompressionFormat.none;

  final String id;
  final String name;
  final String databaseConfigId;
  final DatabaseType databaseType;
  final String scheduleType;
  final String scheduleConfig;
  final List<String> destinationIds;
  final String backupFolder;
  final BackupType backupType;
  final bool truncateLog;
  final bool compressBackup;
  final CompressionFormat? compressionFormat;
  final bool enabled;
  final bool enableChecksum;
  final bool verifyAfterBackup;
  final VerifyPolicy verifyPolicy;
  final String? postBackupScript;
  final Duration backupTimeout;
  final Duration verifyTimeout;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isConvertedDifferential;

  Schedule copyWith({
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
    Duration? backupTimeout,
    Duration? verifyTimeout,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isConvertedDifferential,
  }) {
    return Schedule(
      id: id ?? this.id,
      name: name ?? this.name,
      databaseConfigId: databaseConfigId ?? this.databaseConfigId,
      databaseType: databaseType ?? this.databaseType,
      scheduleType: scheduleType ?? this.scheduleType,
      scheduleConfig: scheduleConfig ?? this.scheduleConfig,
      destinationIds: destinationIds ?? this.destinationIds,
      backupFolder: backupFolder ?? this.backupFolder,
      backupType: backupType ?? this.backupType,
      truncateLog: truncateLog ?? this.truncateLog,
      compressBackup: compressBackup ?? this.compressBackup,
      compressionFormat: compressionFormat ?? this.compressionFormat,
      enabled: enabled ?? this.enabled,
      enableChecksum: enableChecksum ?? this.enableChecksum,
      verifyAfterBackup: verifyAfterBackup ?? this.verifyAfterBackup,
      verifyPolicy: verifyPolicy ?? this.verifyPolicy,
      postBackupScript: postBackupScript ?? this.postBackupScript,
      backupTimeout: backupTimeout ?? this.backupTimeout,
      verifyTimeout: verifyTimeout ?? this.verifyTimeout,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isConvertedDifferential:
          isConvertedDifferential ?? this.isConvertedDifferential,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Schedule && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
