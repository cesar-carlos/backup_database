import 'package:uuid/uuid.dart';

import 'backup_type.dart';

enum ScheduleType { daily, weekly, monthly, interval }

enum DatabaseType { sqlServer, sybase }

class Schedule {
  final String id;
  final String name;
  final String databaseConfigId;
  final DatabaseType databaseType;
  final ScheduleType scheduleType;
  final String scheduleConfig; // JSON com configurações específicas
  final List<String> destinationIds;
  final String backupFolder;
  final BackupType backupType;
  final bool compressBackup;
  final bool enabled;
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
    this.compressBackup = true,
    this.enabled = true,
    this.lastRunAt,
    this.nextRunAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
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
    bool? compressBackup,
    bool? enabled,
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
      compressBackup: compressBackup ?? this.compressBackup,
      enabled: enabled ?? this.enabled,
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

// Configurações específicas para cada tipo de agendamento
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
  final List<int> daysOfWeek; // 1=Segunda, 7=Domingo
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
  final List<int> daysOfMonth; // 1-31
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
