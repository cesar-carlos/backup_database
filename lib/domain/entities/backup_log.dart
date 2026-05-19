import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

part 'backup_log.freezed.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error
  ;

  static LogLevel fromString(String value) {
    final normalized = value.trim().toLowerCase();
    for (final level in LogLevel.values) {
      if (level.name == normalized) return level;
    }
    return LogLevel.info;
  }
}

enum LogCategory { execution, system, audit }

@freezed
abstract class BackupLog with _$BackupLog {
  const BackupLog._();

  factory BackupLog({
    required LogLevel level,
    required LogCategory category,
    required String message,
    String? id,
    String? backupHistoryId,
    String? details,
    DateTime? createdAt,
  }) {
    return BackupLog.raw(
      id: id ?? const Uuid().v4(),
      backupHistoryId: backupHistoryId,
      level: level,
      category: category,
      message: message,
      details: details,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  const factory BackupLog.raw({
    required String id,
    required LogLevel level,
    required LogCategory category,
    required String message,
    required DateTime createdAt,
    String? backupHistoryId,
    String? details,
  }) = _BackupLog;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupLog && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
