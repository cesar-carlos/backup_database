import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:result_dart/result_dart.dart' as rd;

class BackupMetricsReport {
  const BackupMetricsReport({
    required this.startDate,
    required this.endDate,
    required this.metricsByType,
    required this.totalBackups,
  });

  final DateTime startDate;
  final DateTime endDate;
  final Map<BackupType, List<BackupMetrics>> metricsByType;
  final int totalBackups;
}

abstract class IMetricsAnalysisService {
  Future<rd.Result<BackupMetricsReport>> generateReport({
    required DateTime startDate,
    required DateTime endDate,
    String? databaseType,
  });
}
