import 'dart:async';

import 'package:backup_database/application/services/alert_service.dart';
import 'package:backup_database/application/services/health/backup_freshness_probe.dart';
import 'package:backup_database/application/services/health/disk_space_probe.dart';
import 'package:backup_database/application/services/health/health_models.dart';
import 'package:backup_database/application/services/health/postgres_wal_slot_probe.dart';
import 'package:backup_database/application/services/health/success_rate_probe.dart';
import 'package:backup_database/application/services/log_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';

export 'health/health_models.dart';

class ServiceHealthChecker {
  ServiceHealthChecker({
    required IBackupHistoryRepository backupHistoryRepository,
    required ProcessService processService,
    required IPostgresConfigRepository postgresConfigRepository,
    this._logService,
    this._alertService,
    this.checkInterval = const Duration(minutes: 30),
    this.maxBackupAge = const Duration(days: 2),
    this.minSuccessRate = 0.7,
    this.minFreeDiskGB = 5.0,
    List<String> diskCheckPaths = const [],
  }) : _backupFreshnessProbe = BackupFreshnessProbe(
         backupHistoryRepository: backupHistoryRepository,
         maxBackupAge: maxBackupAge,
       ),
       _successRateProbe = SuccessRateProbe(
         backupHistoryRepository: backupHistoryRepository,
         minSuccessRate: minSuccessRate,
       ),
       _diskSpaceProbe = DiskSpaceProbe(
         processService: processService,
         diskCheckPaths: diskCheckPaths,
         minFreeDiskGB: minFreeDiskGB,
       ),
       _postgresWalSlotProbe = PostgresWalSlotProbe(
         processService: processService,
         postgresConfigRepository: postgresConfigRepository,
       );

  final LogService? _logService;
  final AlertService? _alertService;
  final BackupFreshnessProbe _backupFreshnessProbe;
  final SuccessRateProbe _successRateProbe;
  final DiskSpaceProbe _diskSpaceProbe;
  final PostgresWalSlotProbe _postgresWalSlotProbe;

  final Duration checkInterval;
  final Duration maxBackupAge;
  final double minSuccessRate;
  final double minFreeDiskGB;

  Timer? _checkTimer;
  bool _isRunning = false;
  HealthCheckResult? _lastResult;

  int _consecutiveErrors = 0;
  int _skipCyclesRemaining = 0;
  static const int _backoffThreshold = 3;
  static const int _maxBackoffSkipCycles = 8;

  Future<void> start() async {
    if (_isRunning) {
      LoggerService.warning('HealthChecker já está rodando');
      return;
    }

    _isRunning = true;
    LoggerService.info(
      '🩺 ServiceHealthChecker iniciado '
      '(intervalo: ${checkInterval.inMinutes}min)',
    );

    unawaited(_performHealthCheck());

    _checkTimer = Timer.periodic(checkInterval, (_) {
      unawaited(_performHealthCheck());
    });
  }

  void stop() {
    if (!_isRunning) return;

    _isRunning = false;
    _checkTimer?.cancel();
    _checkTimer = null;
    _consecutiveErrors = 0;
    _skipCyclesRemaining = 0;

    LoggerService.info('🩺 ServiceHealthChecker parado');
  }

  Future<HealthCheckResult> checkHealthNow() async {
    return _performHealthCheck();
  }

  Future<HealthCheckResult> _performHealthCheck() async {
    if (_skipCyclesRemaining > 0) {
      _skipCyclesRemaining--;
      LoggerService.debug(
        '🩺 Verificação de saúde adiada (backoff: '
        '${_skipCyclesRemaining + 1} ciclos restantes)',
      );
      return _lastResult ??
          HealthCheckResult(
            status: HealthStatus.warning,
            timestamp: DateTime.now(),
            issues: const [
              HealthIssue(
                severity: HealthStatus.warning,
                category: 'system',
                message: 'Verificação em backoff após falhas consecutivas',
              ),
            ],
          );
    }

    LoggerService.debug('Executando verificação de saúde...');

    final issues = <HealthIssue>[];
    final metrics = <String, dynamic>{};
    final timestamp = DateTime.now();

    try {
      final lastBackupResult = await _backupFreshnessProbe.check(timestamp);
      issues.addAll(lastBackupResult.issues);
      metrics.addAll(lastBackupResult.metrics);

      final successRateResult = await _successRateProbe.check();
      issues.addAll(successRateResult.issues);
      metrics.addAll(successRateResult.metrics);

      final diskSpaceResult = await _diskSpaceProbe.check();
      issues.addAll(diskSpaceResult.issues);
      metrics.addAll(diskSpaceResult.metrics);

      final slotHealthResult = await _postgresWalSlotProbe.check();
      issues.addAll(slotHealthResult.issues);
      metrics.addAll(slotHealthResult.metrics);

      final status = _determineStatus(issues);

      final result = HealthCheckResult(
        status: status,
        timestamp: timestamp,
        issues: issues,
        metrics: metrics,
      );

      _lastResult = result;

      if (_consecutiveErrors > 0) {
        LoggerService.info(
          '🩺 Verificação de saúde recuperada após '
          '$_consecutiveErrors erro(s) consecutivo(s)',
        );
        _consecutiveErrors = 0;
        _skipCyclesRemaining = 0;
      }

      await _publishOperationalAlerts(result);
      _logHealthResult(result);

      return result;
    } on Object catch (e, s) {
      _consecutiveErrors++;

      final skipCycles = _consecutiveErrors >= _backoffThreshold
          ? (_consecutiveErrors - _backoffThreshold + 1).clamp(
              1,
              _maxBackoffSkipCycles,
            )
          : 0;

      if (skipCycles > 0) {
        _skipCyclesRemaining = skipCycles;
        LoggerService.warning(
          '⚠️ Verificação de saúde falhou $_consecutiveErrors vez(es) '
          'consecutiva(s). Próxima execução após $skipCycles ciclo(s) '
          '(≈${skipCycles * checkInterval.inMinutes}min).',
        );
      } else {
        LoggerService.error('Erro durante verificação de saúde', e, s);
      }

      final criticalResult = HealthCheckResult(
        status: HealthStatus.critical,
        timestamp: timestamp,
        issues: [
          HealthIssue(
            severity: HealthStatus.critical,
            category: 'system',
            message:
                'Erro ao executar verificação de saúde: ${_issueMessage(e)}',
          ),
        ],
      );

      _lastResult = criticalResult;
      return criticalResult;
    }
  }

  Future<void> _publishOperationalAlerts(HealthCheckResult result) async {
    final slotIssues = result.issues
        .where((issue) => issue.category == 'postgres_slot')
        .toList();
    if (slotIssues.isEmpty) {
      _alertService?.replaceOperationalAlerts(const []);
      return;
    }

    final alerts = slotIssues
        .map(
          (issue) => BackupAlert(
            type: issue.message.contains('atraso alto')
                ? AlertType.walSlotLag
                : AlertType.walSlotInactive,
            scheduleId: 'postgres-slot-health',
            severity: issue.severity == HealthStatus.critical
                ? AlertSeverity.critical
                : AlertSeverity.high,
            message: issue.message,
          ),
        )
        .toList();
    _alertService?.replaceOperationalAlerts(alerts);

    final logService = _logService;
    if (logService == null) {
      return;
    }

    for (final issue in slotIssues) {
      await logService.log(
        level: issue.severity == HealthStatus.critical
            ? LogLevel.error
            : LogLevel.warning,
        category: LogCategory.system,
        message: issue.message,
        details: issue.details,
      );
    }
  }

  HealthStatus _determineStatus(List<HealthIssue> issues) {
    if (issues.any((i) => i.severity == HealthStatus.critical)) {
      return HealthStatus.critical;
    }

    if (issues.any((i) => i.severity == HealthStatus.warning)) {
      return HealthStatus.warning;
    }

    return HealthStatus.healthy;
  }

  void _logHealthResult(HealthCheckResult result) {
    final emoji = switch (result.status) {
      HealthStatus.healthy => '✅',
      HealthStatus.warning => '⚠️',
      HealthStatus.critical => '❌',
    };

    LoggerService.info(
      '$emoji Verificação de saúde: ${result.status.name.toUpperCase()}',
    );

    if (result.issues.isNotEmpty) {
      for (final issue in result.issues) {
        final level = switch (issue.severity) {
          HealthStatus.critical => 'CRÍTICO',
          HealthStatus.warning => 'AVISO',
          HealthStatus.healthy => 'INFO',
        };

        LoggerService.warning('[$level] ${issue.category}: ${issue.message}');
        if (issue.details != null) {
          LoggerService.debug('  Detalhes: ${issue.details}');
        }
      }
    }

    if (result.metrics.containsKey('last_backup_age_hours')) {
      final age = result.metrics['last_backup_age_hours'] as int;
      LoggerService.debug('  Último backup: ${age}h atrás');
    }

    if (result.metrics.containsKey('success_rate')) {
      final rate = result.metrics['success_rate'] as double;
      LoggerService.debug(
        '  Taxa de sucesso: ${(rate * 100).toStringAsFixed(1)}%',
      );
    }

    if (result.metrics.containsKey('free_disk_gb')) {
      final freeGB = result.metrics['free_disk_gb'] as double;
      LoggerService.debug(
        '  Espaço livre: ${freeGB.toStringAsFixed(2)} GB',
      );
    }
  }

  HealthCheckResult? get lastResult => _lastResult;

  bool get isRunning => _isRunning;

  String _issueMessage(Object? failure) {
    return healthIssueMessage(failure);
  }
}
