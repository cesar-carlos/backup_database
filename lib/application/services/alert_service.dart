import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';

class AlertService {
  final List<BackupAlert> _alerts = [];

  List<BackupAlert> checkAlerts(List<BackupHistory> history) {
    _alerts.clear();

    if (history.isEmpty) {
      return _alerts;
    }

    final bySchedule = <String, List<BackupHistory>>{};
    for (final h in history) {
      final scheduleId = h.scheduleId ?? 'no-schedule';
      bySchedule.putIfAbsent(scheduleId, () => []).add(h);
    }

    for (final entry in bySchedule.entries) {
      final backups = entry.value;
      backups.sort((a, b) => b.startedAt.compareTo(a.startedAt));

      if (_hasConsecutiveFailures(backups)) {
        _alerts.add(
          BackupAlert(
            type: AlertType.consecutiveFailures,
            scheduleId: entry.key,
            severity: AlertSeverity.high,
            message:
                '3 ou mais falhas consecutivas no agendamento ${entry.key}',
          ),
        );
      }

      if (_hasHighErrorRate(backups)) {
        _alerts.add(
          BackupAlert(
            type: AlertType.highErrorRate,
            scheduleId: entry.key,
            severity: AlertSeverity.medium,
            message: 'Taxa de erro acima de 50% no agendamento ${entry.key}',
          ),
        );
      }
    }

    return _alerts;
  }

  bool _hasConsecutiveFailures(
    List<BackupHistory> backups, {
    int threshold = 3,
  }) {
    var consecutive = 0;

    for (final backup in backups) {
      if (backup.status == BackupStatus.error) {
        consecutive++;
        if (consecutive >= threshold) {
          return true;
        }
      } else {
        consecutive = 0;
      }
    }

    return false;
  }

  bool _hasHighErrorRate(
    List<BackupHistory> backups, {
    double threshold = 0.5,
  }) {
    if (backups.length < 3) return false;

    final errorCount = backups
        .where((b) => b.status == BackupStatus.error)
        .length;
    final rate = errorCount / backups.length;

    return rate > threshold;
  }

  List<BackupAlert> getActiveAlerts() => List.unmodifiable(_alerts);

  void clearAlerts() {
    _alerts.clear();
  }

  void logAlerts() {
    for (final alert in _alerts) {
      LoggerService.warning(
        '[ALERTA ${alert.severity.name.toUpperCase()}] ${alert.message}',
      );
    }
  }
}

class BackupAlert {
  BackupAlert({
    required this.type,
    required this.scheduleId,
    required this.severity,
    required this.message,
  });

  final AlertType type;
  final String scheduleId;
  final AlertSeverity severity;
  final String message;

  @override
  String toString() => '[$severity] $message';
}

enum AlertType {
  consecutiveFailures,
  highErrorRate,
  tokenExpiring,
  lowDiskSpace,
}

enum AlertSeverity {
  low,
  medium,
  high,
  critical,
}
