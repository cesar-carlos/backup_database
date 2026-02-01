import 'package:backup_database/domain/entities/backup_history.dart';

/// Tracks backup metrics for monitoring and analysis
class BackupMetricsService {
  final _metrics = <String, _DatabaseMetrics>{};

  /// Record a backup completion
  void recordBackup(BackupHistory history) {
    final key = '${history.databaseType}_${history.backupType}';
    final metrics = _metrics.putIfAbsent(
      key,
      () => _DatabaseMetrics(databaseType: history.databaseType),
    );

    final duration = history.finishedAt != null
        ? history.finishedAt!.difference(history.startedAt)
        : Duration.zero;

    metrics.record(
      fileSize: history.fileSize,
      duration: duration,
      status: history.status,
    );
  }

  /// Get metrics for a specific database type and backup type
  _DatabaseMetrics? getMetrics({
    required String databaseType,
    String? backupType,
  }) {
    final key = backupType != null ? '${databaseType}_$backupType' : databaseType;
    return _metrics[key];
  }

  /// Get all recorded metrics
  Map<String, _DatabaseMetrics> getAllMetrics() => Map.from(_metrics);

  /// Clear all metrics
  void clear() {
    _metrics.clear();
  }

  /// Calculate success rate for all backups
  double getOverallSuccessRate() {
    if (_metrics.isEmpty) return 0;

    var totalBackups = 0;
    var successfulBackups = 0;

    for (final metrics in _metrics.values) {
      totalBackups += metrics.totalCount;
      successfulBackups += metrics.successCount;
    }

    if (totalBackups == 0) return 0;
    return successfulBackups / totalBackups;
  }

  /// Get average backup size in bytes
  int getAverageBackupSize() {
    if (_metrics.isEmpty) return 0;

    var totalSize = 0;
    var count = 0;

    for (final metrics in _metrics.values) {
      if (metrics.totalSize > 0) {
        totalSize += metrics.totalSize;
        count += metrics.successCount;
      }
    }

    if (count == 0) return 0;
    return totalSize ~/ count;
  }
}

class _DatabaseMetrics {
  _DatabaseMetrics({required this.databaseType});

  final String databaseType;
  int totalCount = 0;
  int successCount = 0;
  int errorCount = 0;
  int totalSize = 0;
  final List<Duration> durations = [];

  void record({
    required int fileSize,
    required Duration duration,
    required BackupStatus status,
  }) {
    totalCount++;
    totalSize += fileSize;
    durations.add(duration);

    switch (status) {
      case BackupStatus.success:
        successCount++;
      case BackupStatus.error:
        errorCount++;
      case BackupStatus.warning:
      case BackupStatus.running:
        break;
    }
  }

  /// Get average duration in milliseconds
  double getAverageDuration() {
    if (durations.isEmpty) return 0;

    final totalMs = durations.fold<int>(
      0,
      (sum, duration) => sum + duration.inMilliseconds,
    );

    return totalMs / durations.length;
  }

  /// Get success rate (0.0 to 1.0)
  double getSuccessRate() {
    if (totalCount == 0) return 0;
    return successCount / totalCount;
  }

  /// Get average file size in bytes
  int getAverageFileSize() {
    if (totalCount == 0) return 0;
    return totalSize ~/ totalCount;
  }
}
