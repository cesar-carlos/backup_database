import 'dart:async';

import 'package:backup_database/core/constants/backup_constants.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_audit_retention_scheduler.dart';
import 'package:backup_database/infrastructure/datasources/daos/mutable_command_audit_dao.dart';

/// PR-6: scheduler diario que apaga audit logs anteriores a
/// `BackupConstants.auditRetentionPeriod`. Inicializado em
/// `ServiceModeInitializer` step 10 junto com housekeeping de fila.
class AuditRetentionScheduler implements IAuditRetentionScheduler {
  AuditRetentionScheduler(
    this._auditDao, {
    Duration? interval,
    Duration? retentionPeriod,
    DateTime Function()? clock,
  }) : _interval = interval ?? const Duration(hours: 24),
       _retentionPeriod =
           retentionPeriod ?? BackupConstants.auditRetentionPeriod,
       _clock = clock ?? DateTime.now;

  final MutableCommandAuditDao _auditDao;
  final Duration _interval;
  final Duration _retentionPeriod;
  final DateTime Function() _clock;

  Timer? _timer;

  @override
  void start() {
    if (_timer != null) return;
    LoggerService.info(
      'AuditRetentionScheduler: intervalo='
      '${_interval.inHours}h, '
      'retencao=${_retentionPeriod.inDays}d',
    );
    // Tick imediato para limpar restos da sessao anterior.
    unawaited(_tick());
    _timer = Timer.periodic(_interval, (_) => unawaited(_tick()));
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    try {
      final cutoff = _clock().subtract(_retentionPeriod);
      final deleted = await _auditDao.deleteOlderThan(cutoff);
      if (deleted > 0) {
        LoggerService.info(
          'AuditRetentionScheduler: removidos $deleted audit log(s) '
          'anteriores a ${cutoff.toUtc().toIso8601String()}.',
        );
      }
    } on Object catch (e, st) {
      LoggerService.warning(
        'AuditRetentionScheduler: erro no tick',
        e,
        st,
      );
    }
  }
}
