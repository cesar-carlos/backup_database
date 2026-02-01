import 'package:backup_database/domain/entities/backup_history.dart';

class BackupMetricsService {
  final _metrics = <String, _DatabaseMetrics>{};

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

  Map<String, dynamic>? getMetrics({
    required String databaseType,
    String? backupType,
  }) {
    final key = backupType != null
        ? '${databaseType}_$backupType'
        : databaseType;
    final metrics = _metrics[key];
    if (metrics == null) return null;
    return {
      'databaseType': metrics.databaseType,
      'totalCount': metrics.totalCount,
      'successCount': metrics.successCount,
      'errorCount': metrics.errorCount,
      'totalSize': metrics.totalSize,
      'averageDuration': metrics.getAverageDuration(),
      'successRate': metrics.getSuccessRate(),
      'averageFileSize': metrics.getAverageFileSize(),
    };
  }

  Map<String, Map<String, dynamic>> getAllMetrics() {
    return _metrics.map(
      (key, value) => MapEntry(
        key,
        {
          'databaseType': value.databaseType,
          'totalCount': value.totalCount,
          'successCount': value.successCount,
          'errorCount': value.errorCount,
          'totalSize': value.totalSize,
          'averageDuration': value.getAverageDuration(),
          'successRate': value.getSuccessRate(),
          'averageFileSize': value.getAverageFileSize(),
        },
      ),
    );
  }

  void clear() {
    _metrics.clear();
  }

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

  double getAverageDuration() {
    if (durations.isEmpty) return 0;

    final totalMs = durations.fold<int>(
      0,
      (sum, duration) => sum + duration.inMilliseconds,
    );

    return totalMs / durations.length;
  }

  double getSuccessRate() {
    if (totalCount == 0) return 0;
    return successCount / totalCount;
  }

  int getAverageFileSize() {
    if (totalCount == 0) return 0;
    return totalSize ~/ totalCount;
  }
}
