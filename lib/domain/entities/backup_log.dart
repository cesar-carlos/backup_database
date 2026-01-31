import 'package:uuid/uuid.dart';

enum LogLevel { debug, info, warning, error }

enum LogCategory { execution, system, audit }

class BackupLog {
  BackupLog({
    required this.level,
    required this.category,
    required this.message,
    String? id,
    this.backupHistoryId,
    this.details,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();
  final String id;
  final String? backupHistoryId;
  final LogLevel level;
  final LogCategory category;
  final String message;
  final String? details;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupLog && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
