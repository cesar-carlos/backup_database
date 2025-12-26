import 'package:uuid/uuid.dart';

import 'backup_type.dart';
import 'compression_format.dart';

enum ScheduleType { daily, weekly, monthly, interval }

enum DatabaseType { sqlServer, sybase, postgresql }

class Schedule {
  final String id;
  final String name;
  final String databaseConfigId;
  final DatabaseType databaseType;
  final ScheduleType scheduleType;
  final String scheduleConfig;
  final List<String> destinationIds;
  final String backupFolder;
  final BackupType backupType;
  final bool truncateLog;
  final bool compressBackup;
  final CompressionFormat compressionFormat;
  final bool enabled;
  final bool enableChecksum;
  final bool verifyAfterBackup;
  final String? postBackupScript;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Schedule({
    String? id,
    required this.name,
    required this.databaseConfigId,
    required this.databaseType,
    required this.scheduleType,
    required this.scheduleConfig,
    required this.destinationIds,
    required this.backupFolder,
    this.backupType = BackupType.full,
    this.truncateLog = true,
    this.compressBackup = true,
    CompressionFormat? compressionFormat,
    this.enabled = true,
    this.enableChecksum = false,
    this.verifyAfterBackup = false,
    this.postBackupScript,
    this.lastRunAt,
    this.nextRunAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       compressionFormat =
           compressionFormat ??
           (compressBackup ? CompressionFormat.zip : CompressionFormat.none),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Schedule copyWith({
    String? id,
    String? name,
    String? databaseConfigId,
    DatabaseType? databaseType,
    ScheduleType? scheduleType,
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
    String? postBackupScript,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    DateTime? createdAt,
    DateTime? updatedAt,
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
      compressionFormat: () {
        final willCompress = compressBackup ?? this.compressBackup;
        if (!willCompress) {
          return CompressionFormat.none;
        }
        if (compressionFormat != null) {
          return compressionFormat;
        }
        if (this.compressionFormat == CompressionFormat.none) {
          return CompressionFormat.zip;
        }
        return this.compressionFormat;
      }(),
      enabled: enabled ?? this.enabled,
      enableChecksum: enableChecksum ?? this.enableChecksum,
      verifyAfterBackup: verifyAfterBackup ?? this.verifyAfterBackup,
      postBackupScript: postBackupScript ?? this.postBackupScript,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Schedule && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class DailyScheduleConfig {
  final int hour;
  final int minute;

  const DailyScheduleConfig({required this.hour, required this.minute});

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  factory DailyScheduleConfig.fromJson(Map<String, dynamic> json) {
    return DailyScheduleConfig(
      hour: json['hour'] as int,
      minute: json['minute'] as int,
    );
  }
}

class WeeklyScheduleConfig {
  final List<int> daysOfWeek;
  final int hour;
  final int minute;

  const WeeklyScheduleConfig({
    required this.daysOfWeek,
    required this.hour,
    required this.minute,
  });

  Map<String, dynamic> toJson() => {
    'daysOfWeek': daysOfWeek,
    'hour': hour,
    'minute': minute,
  };

  factory WeeklyScheduleConfig.fromJson(Map<String, dynamic> json) {
    return WeeklyScheduleConfig(
      daysOfWeek: (json['daysOfWeek'] as List).cast<int>(),
      hour: json['hour'] as int,
      minute: json['minute'] as int,
    );
  }
}

class MonthlyScheduleConfig {
  final List<int> daysOfMonth;
  final int hour;
  final int minute;

  const MonthlyScheduleConfig({
    required this.daysOfMonth,
    required this.hour,
    required this.minute,
  });

  Map<String, dynamic> toJson() => {
    'daysOfMonth': daysOfMonth,
    'hour': hour,
    'minute': minute,
  };

  factory MonthlyScheduleConfig.fromJson(Map<String, dynamic> json) {
    return MonthlyScheduleConfig(
      daysOfMonth: (json['daysOfMonth'] as List).cast<int>(),
      hour: json['hour'] as int,
      minute: json['minute'] as int,
    );
  }
}

class IntervalScheduleConfig {
  final int intervalMinutes;

  const IntervalScheduleConfig({required this.intervalMinutes});

  Map<String, dynamic> toJson() => {'intervalMinutes': intervalMinutes};

  factory IntervalScheduleConfig.fromJson(Map<String, dynamic> json) {
    return IntervalScheduleConfig(
      intervalMinutes: json['intervalMinutes'] as int,
    );
  }
}
