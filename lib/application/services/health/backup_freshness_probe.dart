import 'package:backup_database/application/services/health/health_models.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/repositories/repositories.dart';

class BackupFreshnessProbe {
  BackupFreshnessProbe({
    required this._backupHistoryRepository,
    required this.maxBackupAge,
  });

  static const int _recentHistoryLimit = 10;

  final IBackupHistoryRepository _backupHistoryRepository;
  final Duration maxBackupAge;

  Future<HealthProbeResult> check(DateTime now) async {
    final issues = <HealthIssue>[];
    final metrics = <String, dynamic>{};

    try {
      final result = await _backupHistoryRepository.getAll(
        limit: _recentHistoryLimit,
      );

      result.fold(
        (histories) {
          if (histories.isEmpty) {
            issues.add(
              const HealthIssue(
                severity: HealthStatus.warning,
                category: 'backup',
                message: 'Nenhum backup encontrado no histórico',
              ),
            );
            return;
          }

          final lastBackup = histories.first;
          final age = now.difference(lastBackup.startedAt);

          metrics['last_backup_age_hours'] = age.inHours;
          metrics['last_backup_status'] = lastBackup.status.name;
          metrics['last_backup_date'] = lastBackup.startedAt.toIso8601String();

          if (age > maxBackupAge) {
            issues.add(
              HealthIssue(
                severity: HealthStatus.warning,
                category: 'backup',
                message:
                    'Último backup executado há ${age.inDays} dias '
                    '(máximo: ${maxBackupAge.inDays} dias)',
                details: 'Data: ${lastBackup.startedAt}',
              ),
            );
          }

          if (lastBackup.status == BackupStatus.error) {
            issues.add(
              HealthIssue(
                severity: HealthStatus.critical,
                category: 'backup',
                message: 'Último backup falhou',
                details: lastBackup.errorMessage ?? 'Sem detalhes',
              ),
            );
          }
        },
        (failure) {
          issues.add(
            HealthIssue(
              severity: HealthStatus.warning,
              category: 'backup',
              message:
                  'Erro ao buscar histórico de backups: '
                  '${_issueMessage(failure)}',
            ),
          );
        },
      );
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao verificar último backup', e, s);
      issues.add(
        HealthIssue(
          severity: HealthStatus.warning,
          category: 'backup',
          message: 'Exceção ao verificar último backup: ${_issueMessage(e)}',
        ),
      );
    }

    return HealthProbeResult(issues, metrics);
  }

  String _issueMessage(Object? failure) => healthIssueMessage(failure);
}
