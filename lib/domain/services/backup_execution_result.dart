import 'package:backup_database/domain/entities/backup_metrics.dart';

class BackupExecutionResult {
  const BackupExecutionResult({
    required this.backupPath,
    required this.fileSize,
    required this.duration,
    required this.databaseName,
    this.metrics,
  });
  final String backupPath;
  final int fileSize;
  final Duration duration;
  final String databaseName;
  final BackupMetrics? metrics;
}
