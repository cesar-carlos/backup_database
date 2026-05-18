import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

part 'backup_history.freezed.dart';

enum BackupStatus { success, error, warning, running }

@freezed
abstract class BackupHistory with _$BackupHistory {
  const BackupHistory._();

  factory BackupHistory({
    required String databaseName,
    required String databaseType,
    required String backupPath,
    required int fileSize,
    required BackupStatus status,
    required DateTime startedAt,
    String? id,
    String? runId,
    String? scheduleId,
    String backupType = 'full',
    String? errorMessage,
    DateTime? finishedAt,
    int? durationSeconds,
    BackupMetrics? metrics,
  }) {
    return BackupHistory.raw(
      id: id ?? const Uuid().v4(),
      runId: runId,
      scheduleId: scheduleId,
      databaseName: databaseName,
      databaseType: databaseType,
      backupPath: backupPath,
      fileSize: fileSize,
      backupType: backupType,
      status: status,
      errorMessage: errorMessage,
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationSeconds: durationSeconds,
      metrics: metrics,
    );
  }

  const factory BackupHistory.raw({
    required String id,
    required String databaseName, required String databaseType, required String backupPath, required int fileSize, required BackupStatus status, required DateTime startedAt, String? runId,
    String? scheduleId,
    @Default('full') String backupType,
    String? errorMessage,
    DateTime? finishedAt,
    int? durationSeconds,
    BackupMetrics? metrics,
  }) = _BackupHistory;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupHistory &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
