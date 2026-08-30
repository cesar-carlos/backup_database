import 'package:backup_database/application/services/health/health_models.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/repositories/repositories.dart';

class SuccessRateProbe {
  SuccessRateProbe({
    required this._backupHistoryRepository,
    required this.minSuccessRate,
  });

  static const Duration _lookback = Duration(days: 7);

  final IBackupHistoryRepository _backupHistoryRepository;
  final double minSuccessRate;

  Future<HealthProbeResult> check() async {
    final issues = <HealthIssue>[];
    final metrics = <String, dynamic>{};

    try {
      final sevenDaysAgo = DateTime.now().subtract(_lookback);
      final result = await _backupHistoryRepository.getByDateRange(
        sevenDaysAgo,
        DateTime.now(),
      );

      result.fold(
        (histories) {
          if (histories.isEmpty) {
            metrics['success_rate'] = 0.0;
            return;
          }

          final successCount = histories
              .where((h) => h.status == BackupStatus.success)
              .length;
          final totalCount = histories.length;
          final successRate = successCount / totalCount;

          metrics['success_rate'] = successRate;
          metrics['total_backups_7d'] = totalCount;
          metrics['success_backups_7d'] = successCount;

          if (successRate < minSuccessRate) {
            issues.add(
              HealthIssue(
                severity: HealthStatus.warning,
                category: 'backup',
                message:
                    'Taxa de sucesso baixa: '
                    '${(successRate * 100).toStringAsFixed(1)}% '
                    '(mínimo: ${(minSuccessRate * 100).toStringAsFixed(0)}%)',
                details: '$successCount/$totalCount backups bem-sucedidos',
              ),
            );
          }
        },
        (failure) {},
      );
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao calcular taxa de sucesso', e, s);
    }

    return HealthProbeResult(issues, metrics);
  }
}
