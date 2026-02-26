import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:result_dart/result_dart.dart' as rd;

class MetricsAnalysisService implements IMetricsAnalysisService {
  final IBackupHistoryRepository _historyRepository;

  MetricsAnalysisService(this._historyRepository);

  @override
  Future<rd.Result<BackupMetricsReport>> generateReport({
    required DateTime startDate,
    required DateTime endDate,
    String? databaseType,
  }) async {
    final result = await _historyRepository.getAll();

    return result.fold(
      (histories) {
        final metricsByType = <BackupType, List<BackupMetrics>>{};
        final backups = <String, int>{};

        for (final history in histories) {
          final type = _getBackupType(history);
          metricsByType[type] ??= [];

          final sizeInBytes = history.fileSize;
          backups[history.backupType] ??= sizeInBytes;

          if (sizeInBytes > 0) {
            final duration = Duration(
              seconds: history.durationSeconds ?? 0,
            );

            final metrics = history.metrics;
            final flags =
                metrics?.flags ??
                const BackupFlags(
                  compression: false,
                  verifyPolicy: 'none',
                  stripingCount: 1,
                  withChecksum: false,
                  stopOnError: true,
                );

            metricsByType[type]!.add(
              BackupMetrics(
                totalDuration: duration,
                backupDuration: duration,
                verifyDuration: Duration.zero,
                backupSizeBytes: sizeInBytes,
                backupSpeedMbPerSec: _calculateSpeedMbPerSec(
                  sizeInBytes,
                  duration.inSeconds,
                ),
                backupType: type.name,
                flags: flags,
              ),
            );
          }
        }

        final percentilesByType =
            _computePercentilesByType(metricsByType);

        return rd.Success(
          BackupMetricsReport(
            startDate: startDate,
            endDate: endDate,
            metricsByType: metricsByType,
            totalBackups: backups.length,
            percentilesByType: percentilesByType,
          ),
        );
      },
      rd.Failure.new,
    );
  }

  Map<BackupType, BackupMetricsPercentiles> _computePercentilesByType(
    Map<BackupType, List<BackupMetrics>> metricsByType,
  ) {
    final result = <BackupType, BackupMetricsPercentiles>{};
    for (final entry in metricsByType.entries) {
      final list = entry.value;
      if (list.isEmpty) continue;

      final durations =
          list.map((m) => m.totalDuration.inSeconds).toList()..sort();
      final sizes = list.map((m) => m.backupSizeBytes).toList()..sort();
      final speeds = list.map((m) => m.backupSpeedMbPerSec).toList()..sort();

      final p50Idx = _percentileIndex(list.length, 0.5);
      final p95Idx = _percentileIndex(list.length, 0.95);

      result[entry.key] = BackupMetricsPercentiles(
        sampleCount: list.length,
        p50DurationSeconds: durations[p50Idx],
        p95DurationSeconds: durations[p95Idx],
        p50SizeBytes: sizes[p50Idx],
        p95SizeBytes: sizes[p95Idx],
        p50SpeedMbPerSec: speeds[p50Idx],
        p95SpeedMbPerSec: speeds[p95Idx],
      );
    }
    return result;
  }

  int _percentileIndex(int length, double p) {
    if (length <= 1) return 0;
    final index = (p * (length - 1)).round();
    return index.clamp(0, length - 1);
  }

  BackupType _getBackupType(BackupHistory history) {
    if (history.metrics != null) {
      return backupTypeFromString(history.backupType);
    }
    return BackupType.full;
  }

  double _calculateSpeedMbPerSec(int sizeInBytes, int durationSeconds) {
    if (durationSeconds <= 0) return 0;
    final sizeInMb = sizeInBytes / 1024 / 1024;
    return sizeInMb / durationSeconds;
  }
}
