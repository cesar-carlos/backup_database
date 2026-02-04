import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';

enum HealthStatus {
  healthy,

  warning,

  critical,
}

class HealthCheckResult {
  const HealthCheckResult({
    required this.status,
    required this.timestamp,
    this.issues = const [],
    this.metrics = const {},
  });

  final HealthStatus status;
  final DateTime timestamp;
  final List<HealthIssue> issues;
  final Map<String, dynamic> metrics;

  @override
  String toString() {
    return 'HealthCheckResult(status: $status, issues: ${issues.length}, '
        'timestamp: $timestamp)';
  }
}

class HealthIssue {
  const HealthIssue({
    required this.severity,
    required this.category,
    required this.message,
    this.details,
  });

  final HealthStatus severity;
  final String category;
  final String message;
  final String? details;

  @override
  String toString() {
    return 'HealthIssue($severity: $message)';
  }
}

class ServiceHealthChecker {
  ServiceHealthChecker({
    required IBackupHistoryRepository backupHistoryRepository,
    required ProcessService processService,
    this.checkInterval = const Duration(minutes: 30),
    this.maxBackupAge = const Duration(days: 2),
    this.minSuccessRate = 0.7,
    this.minFreeDiskGB = 5.0,
  })  : _backupHistoryRepository = backupHistoryRepository,
        _processService = processService;

  final IBackupHistoryRepository _backupHistoryRepository;
  final ProcessService _processService;

  final Duration checkInterval;

  final Duration maxBackupAge;

  final double minSuccessRate;

  final double minFreeDiskGB;

  Timer? _checkTimer;
  bool _isRunning = false;
  HealthCheckResult? _lastResult;

  Future<void> start() async {
    if (_isRunning) {
      LoggerService.warning('HealthChecker já está rodando');
      return;
    }

    _isRunning = true;
    LoggerService.info(
      '🩺 ServiceHealthChecker iniciado (intervalo: ${checkInterval.inMinutes}min)',
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

    LoggerService.info('🩺 ServiceHealthChecker parado');
  }

  Future<HealthCheckResult> checkHealthNow() async {
    return _performHealthCheck();
  }

  Future<HealthCheckResult> _performHealthCheck() async {
    LoggerService.debug('Executando verificação de saúde...');

    final issues = <HealthIssue>[];
    final metrics = <String, dynamic>{};
    final timestamp = DateTime.now();

    try {
      final lastBackupResult = await _checkLastBackup(timestamp);
      issues.addAll(lastBackupResult.issues);
      metrics.addAll(lastBackupResult.metrics);

      final successRateResult = await _checkSuccessRate();
      issues.addAll(successRateResult.issues);
      metrics.addAll(successRateResult.metrics);

      final diskSpaceResult = await _checkDiskSpace();
      issues.addAll(diskSpaceResult.issues);
      metrics.addAll(diskSpaceResult.metrics);

      final status = _determineStatus(issues);

      final result = HealthCheckResult(
        status: status,
        timestamp: timestamp,
        issues: issues,
        metrics: metrics,
      );

      _lastResult = result;

      _logHealthResult(result);

      return result;
    } on Object catch (e, s) {
      LoggerService.error('Erro durante verificação de saúde', e, s);

      final criticalResult = HealthCheckResult(
        status: HealthStatus.critical,
        timestamp: timestamp,
        issues: [
          HealthIssue(
            severity: HealthStatus.critical,
            category: 'system',
            message: 'Erro ao executar verificação de saúde: $e',
          ),
        ],
      );

      _lastResult = criticalResult;
      return criticalResult;
    }
  }

  Future<_CheckResult> _checkLastBackup(DateTime now) async {
    final issues = <HealthIssue>[];
    final metrics = <String, dynamic>{};

    try {
      final result = await _backupHistoryRepository.getAll(limit: 10);

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
                  'Erro ao buscar histórico de backups: $failure',
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
          message: 'Exceção ao verificar último backup: $e',
        ),
      );
    }

    return _CheckResult(issues, metrics);
  }

  Future<_CheckResult> _checkSuccessRate() async {
    final issues = <HealthIssue>[];
    final metrics = <String, dynamic>{};

    try {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
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
                    'Taxa de sucesso baixa: ${(successRate * 100).toStringAsFixed(1)}% '
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

    return _CheckResult(issues, metrics);
  }

  Future<_CheckResult> _checkDiskSpace() async {
    final issues = <HealthIssue>[];
    final metrics = <String, dynamic>{};

    if (!Platform.isWindows) {
      metrics['disk_check_performed'] = false;
      metrics['disk_check_skip_reason'] = 'Not Windows';
      return _CheckResult(issues, metrics);
    }

    try {
      final currentDir = Directory.current;

      final result = await _processService.run(
        executable: 'fsutil',
        arguments: ['volume', 'diskfree', currentDir.path],
        timeout: const Duration(seconds: 10),
      );

      result.fold(
        (processResult) {
          if (processResult.exitCode != 0) {
            LoggerService.warning(
              'fsutil falhou (exit code: ${processResult.exitCode}): '
              '${processResult.stderr}',
            );
            metrics['disk_check_performed'] = false;
            metrics['disk_check_error'] = processResult.stderr;
            return;
          }

          final output = processResult.stdout.trim();

          final lines = output.split('\n');
          double totalFreeSpaceGB = 0;

          for (final line in lines) {
            if (line.contains('Total free bytes')) {
              final parts = line.split(':');
              if (parts.length >= 2) {
                final bytesStr = parts[1].trim();
                final commasRemoved = bytesStr.replaceAll(',', '');
                final totalFreeBytes = int.tryParse(commasRemoved);

                if (totalFreeBytes != null) {
                  totalFreeSpaceGB = totalFreeBytes / (1024 * 1024 * 1024);
                }
              }
            }
          }

          metrics['disk_check_performed'] = true;
          metrics['free_disk_gb'] = totalFreeSpaceGB;

          if (totalFreeSpaceGB < minFreeDiskGB) {
            issues.add(
              HealthIssue(
                severity: totalFreeSpaceGB < 1.0
                    ? HealthStatus.critical
                    : HealthStatus.warning,
                category: 'disk',
                message:
                    'Espaço em disco baixo: ${totalFreeSpaceGB.toStringAsFixed(2)} GB livre '
                    '(mínimo: ${minFreeDiskGB.toStringAsFixed(1)} GB)',
                details: 'Diretório verificado: ${currentDir.path}',
              ),
            );
          } else {
            LoggerService.debug(
              'Espaço em disco OK: ${totalFreeSpaceGB.toStringAsFixed(2)} GB livre',
            );
          }
        },
        (failure) {
          LoggerService.warning('Erro ao executar fsutil: $failure');
          metrics['disk_check_performed'] = false;
          metrics['disk_check_error'] = failure.toString();
        },
      );
    } on Object catch (e, s) {
      LoggerService.warning('Exceção ao verificar espaço em disco', e, s);
      metrics['disk_check_performed'] = false;
      metrics['disk_check_exception'] = e.toString();
    }

    return _CheckResult(issues, metrics);
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
}

class _CheckResult {
  const _CheckResult(this.issues, this.metrics);

  final List<HealthIssue> issues;
  final Map<String, dynamic> metrics;
}
