import 'dart:io';

import 'package:backup_database/application/services/health/health_models.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/infrastructure/external/process/postgres_wal_slot_utils.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class PostgresWalSlotProbe {
  PostgresWalSlotProbe({
    required this._processService,
    required this._postgresConfigRepository,
  });

  static const double _defaultMaxLagMb = 1024;
  static const double _defaultMaxInactiveHours = 24;
  static const double _bytesPerMb = 1024 * 1024;
  static const double _secondsPerHour = 3600;
  static const Duration _psqlTimeout = Duration(seconds: 30);
  static const String _enabledEnvKey = 'BACKUP_DATABASE_PG_SLOT_HEALTH_ENABLED';
  static const String _maxLagEnvKey = 'BACKUP_DATABASE_PG_SLOT_MAX_LAG_MB';
  static const String _inactiveHoursEnvKey =
      'BACKUP_DATABASE_PG_SLOT_INACTIVE_HOURS';

  final ProcessService _processService;
  final IPostgresConfigRepository _postgresConfigRepository;

  Future<HealthProbeResult> check() async {
    final issues = <HealthIssue>[];
    final metrics = <String, dynamic>{};

    final enabled = _isWalSlotHealthCheckEnabled();
    metrics['wal_slot_health_check_enabled'] = enabled;
    if (!enabled) {
      return HealthProbeResult(issues, metrics);
    }

    final maxLagMb = _slotLagThresholdMb();
    final maxInactiveHours = _slotInactiveThresholdHours();
    metrics['wal_slot_max_lag_mb'] = maxLagMb;
    metrics['wal_slot_max_inactive_hours'] = maxInactiveHours;

    final configsResult = await _postgresConfigRepository.getEnabled();
    if (configsResult.isError()) {
      final failure = configsResult.exceptionOrNull();
      issues.add(
        HealthIssue(
          severity: HealthStatus.warning,
          category: 'postgres_slot',
          message:
              'Falha ao carregar configuracoes PostgreSQL para health '
              'check de slot: ${_issueMessage(failure)}',
        ),
      );
      return HealthProbeResult(issues, metrics);
    }

    final configs = configsResult.getOrNull()!;
    var checkedConfigs = 0;
    var checkedSlots = 0;

    for (final config in configs) {
      checkedConfigs++;
      final slotResult = await _queryWalSlotHealth(config);

      slotResult.fold(
        (slots) {
          checkedSlots += slots.length;
          for (final slot in slots) {
            final lagMb = slot.lagBytes / _bytesPerMb;
            final inactiveHours = slot.inactiveSeconds != null
                ? slot.inactiveSeconds! / _secondsPerHour
                : null;

            if (lagMb >= maxLagMb) {
              issues.add(
                HealthIssue(
                  severity: lagMb >= (maxLagMb * 2)
                      ? HealthStatus.critical
                      : HealthStatus.warning,
                  category: 'postgres_slot',
                  message:
                      'Slot WAL com atraso alto '
                      '(${lagMb.toStringAsFixed(1)} MB): ${slot.slotName}',
                  details:
                      'Config: ${config.name} | Host: ${config.host} | '
                      'Limite: ${maxLagMb.toStringAsFixed(1)} MB',
                ),
              );
            }

            if (!slot.active && inactiveHours != null) {
              if (inactiveHours >= maxInactiveHours) {
                issues.add(
                  HealthIssue(
                    severity: inactiveHours >= (maxInactiveHours * 2)
                        ? HealthStatus.critical
                        : HealthStatus.warning,
                    category: 'postgres_slot',
                    message:
                        'Slot WAL inativo por '
                        '${inactiveHours.toStringAsFixed(1)}h: '
                        '${slot.slotName}',
                    details:
                        'Config: ${config.name} | Host: ${config.host} | '
                        'Limite: ${maxInactiveHours.toStringAsFixed(1)}h',
                  ),
                );
              }
            }
          }
        },
        (failure) {
          issues.add(
            HealthIssue(
              severity: HealthStatus.warning,
              category: 'postgres_slot',
              message:
                  'Falha ao verificar slots WAL em ${config.name}: '
                  '${_issueMessage(failure)}',
            ),
          );
        },
      );
    }

    metrics['wal_slot_checked_configs'] = checkedConfigs;
    metrics['wal_slot_checked_slots'] = checkedSlots;
    return HealthProbeResult(issues, metrics);
  }

  bool _isWalSlotHealthCheckEnabled() {
    final raw = Platform.environment[_enabledEnvKey];
    if (raw == null || raw.trim().isEmpty) {
      return PostgresWalSlotUtils.isWalSlotEnabled(
        environment: Platform.environment,
      );
    }

    final normalized = raw.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on';
  }

  double _slotLagThresholdMb() {
    final raw = Platform.environment[_maxLagEnvKey];
    final parsed = double.tryParse(raw ?? '');
    if (parsed == null || parsed <= 0) {
      return _defaultMaxLagMb;
    }
    return parsed;
  }

  double _slotInactiveThresholdHours() {
    final raw = Platform.environment[_inactiveHoursEnvKey];
    final parsed = double.tryParse(raw ?? '');
    if (parsed == null || parsed <= 0) {
      return _defaultMaxInactiveHours;
    }
    return parsed;
  }

  Future<rd.Result<List<_WalSlotHealthSnapshot>>> _queryWalSlotHealth(
    PostgresConfig config,
  ) async {
    final withInactiveSince = await _runWalSlotHealthQuery(
      config,
      includeInactiveSince: true,
    );
    if (!withInactiveSince.isError()) {
      return withInactiveSince;
    }

    return _runWalSlotHealthQuery(config, includeInactiveSince: false);
  }

  Future<rd.Result<List<_WalSlotHealthSnapshot>>> _runWalSlotHealthQuery(
    PostgresConfig config, {
    required bool includeInactiveSince,
  }) async {
    final inactiveExpr = includeInactiveSince
        ? 'COALESCE(EXTRACT(EPOCH FROM (now() - inactive_since))::bigint, 0)'
        : '0';

    final sql =
        'SELECT slot_name, active::text, '
        'COALESCE(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn), 0)::bigint, '
        '$inactiveExpr '
        "FROM pg_replication_slots WHERE slot_type = 'physical';";

    final arguments = <String>[
      '-h',
      config.host,
      '-p',
      config.portValue.toString(),
      '-U',
      config.username,
      '-d',
      config.databaseValue,
      '-t',
      '-A',
      '-F',
      '|',
      '-c',
      sql,
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};
    final result = await _processService.run(
      executable: 'psql',
      arguments: arguments,
      environment: environment,
      timeout: _psqlTimeout,
    );

    return result.fold(
      (processResult) {
        if (!processResult.isSuccess) {
          return rd.Failure(
            Exception(
              processResult.stderr.isNotEmpty
                  ? processResult.stderr
                  : processResult.stdout,
            ),
          );
        }

        final lines = processResult.stdout
            .split(RegExp(r'[\r\n]+'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();

        final snapshots = <_WalSlotHealthSnapshot>[];
        for (final line in lines) {
          final parts = line.split('|');
          if (parts.length < 4) {
            continue;
          }

          snapshots.add(
            _WalSlotHealthSnapshot(
              slotName: parts[0].trim(),
              active:
                  parts[1].trim().toLowerCase() == 't' ||
                  parts[1].trim().toLowerCase() == 'true',
              lagBytes: int.tryParse(parts[2].trim()) ?? 0,
              inactiveSeconds: int.tryParse(parts[3].trim()),
            ),
          );
        }

        return rd.Success(snapshots);
      },
      (failure) => rd.Failure(Exception(failureUserMessage(failure))),
    );
  }

  String _issueMessage(Object? failure) => healthIssueMessage(failure);
}

class _WalSlotHealthSnapshot {
  const _WalSlotHealthSnapshot({
    required this.slotName,
    required this.active,
    required this.lagBytes,
    required this.inactiveSeconds,
  });

  final String slotName;
  final bool active;
  final int lagBytes;
  final int? inactiveSeconds;
}
