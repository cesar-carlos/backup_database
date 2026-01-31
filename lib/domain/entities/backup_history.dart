import 'package:uuid/uuid.dart';

enum BackupStatus { success, error, warning, running }

class BackupHistory {
  BackupHistory({
    required this.databaseName,
    required this.databaseType,
    required this.backupPath,
    required this.fileSize,
    required this.status,
    required this.startedAt,
    String? id,
    this.scheduleId,
    this.backupType = 'full',
    this.errorMessage,
    this.finishedAt,
    this.durationSeconds,
  }) : id = id ?? const Uuid().v4();
  final String id;
  final String? scheduleId;
  final String databaseName;
  final String databaseType;
  final String backupPath;
  final int fileSize;
  final String backupType;
  final BackupStatus status;
  final String? errorMessage;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? durationSeconds;

  BackupHistory copyWith({
    String? id,
    String? scheduleId,
    String? databaseName,
    String? databaseType,
    String? backupPath,
    int? fileSize,
    String? backupType,
    BackupStatus? status,
    String? errorMessage,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? durationSeconds,
  }) {
    return BackupHistory(
      id: id ?? this.id,
      scheduleId: scheduleId ?? this.scheduleId,
      databaseName: databaseName ?? this.databaseName,
      databaseType: databaseType ?? this.databaseType,
      backupPath: backupPath ?? this.backupPath,
      fileSize: fileSize ?? this.fileSize,
      backupType: backupType ?? this.backupType,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupHistory &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
