import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:result_dart/result_dart.dart' as rd;

class BackupMetricsPercentiles {
  const BackupMetricsPercentiles({
    required this.sampleCount,
    required this.p50DurationSeconds,
    required this.p95DurationSeconds,
    required this.p50SizeBytes,
    required this.p95SizeBytes,
    required this.p50SpeedMbPerSec,
    required this.p95SpeedMbPerSec,
  });

  final int sampleCount;
  final int p50DurationSeconds;
  final int p95DurationSeconds;
  final int p50SizeBytes;
  final int p95SizeBytes;
  final double p50SpeedMbPerSec;
  final double p95SpeedMbPerSec;
}

class BackupMetricsReport {
  const BackupMetricsReport({
    required this.startDate,
    required this.endDate,
    required this.metricsByType,
    required this.totalBackups,
    this.percentilesByType = const {},
  });

  final DateTime startDate;
  final DateTime endDate;
  final Map<BackupType, List<BackupMetrics>> metricsByType;
  final int totalBackups;
  final Map<BackupType, BackupMetricsPercentiles> percentilesByType;
}

abstract class IMetricsAnalysisService {
  Future<rd.Result<BackupMetricsReport>> generateReport({
    required DateTime startDate,
    required DateTime endDate,
    String? databaseType,
  });
}
