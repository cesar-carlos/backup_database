import 'dart:async';

import 'package:backup_database/application/services/scheduler/scheduler_execution_lock.dart';
import 'package:backup_database/core/constants/backup_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SchedulerWatchdog {
  SchedulerWatchdog({
    required this._progressNotifier,
    required this._lock,
    required this._cancelExecution,
    required this._isRunning,
  });

  final IBackupProgressNotifier _progressNotifier;
  final SchedulerExecutionLock _lock;
  final Future<rd.Result<void>> Function(String scheduleId) _cancelExecution;
  final bool Function() _isRunning;

  Timer? _watchdogTimer;
  late final void Function() _progressListener = _onProgress;

  void start() {
    _progressNotifier.addListener(_progressListener);
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(
      BackupConstants.watchdogCheckInterval,
      (_) => unawaited(checkNow()),
    );
    LoggerService.info(
      'Watchdog runtime iniciado: '
      'heartbeat=${BackupConstants.runningHeartbeatTimeout.inMinutes}min, '
      'hardLimit=${BackupConstants.runningMaxDuration.inHours}h, '
      'interval=${BackupConstants.watchdogCheckInterval.inSeconds}s',
    );
  }

  void stop() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    try {
      _progressNotifier.removeListener(_progressListener);
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao remover listener do watchdog (best-effort)',
        e,
      );
    }
    _lock.lastProgressAtByScheduleId.clear();
    _lock.startedAtByScheduleId.clear();
    _lock.watchdogCancelReasonByScheduleId.clear();
  }

  void _onProgress() {
    if (_lock.executingSchedules.isEmpty) return;
    final now = DateTime.now();
    for (final scheduleId in _lock.executingSchedules) {
      _lock.lastProgressAtByScheduleId[scheduleId] = now;
    }
  }

  Future<void> checkNow() async {
    if (!_isRunning() || _lock.executingSchedules.isEmpty) return;
    final now = DateTime.now();
    const heartbeatTimeout = BackupConstants.runningHeartbeatTimeout;
    const hardLimit = BackupConstants.runningMaxDuration;

    final running = _lock.executingSchedules.toList(growable: false);
    for (final scheduleId in running) {
      try {
        final startedAt = _lock.startedAtByScheduleId[scheduleId];
        if (startedAt != null && now.difference(startedAt) > hardLimit) {
          LoggerService.warning(
            'Watchdog: hard limit excedido para scheduleId=$scheduleId '
            '(rodando ha ${now.difference(startedAt).inMinutes}min, '
            'limite=${hardLimit.inMinutes}min)',
          );
          _lock.watchdogCancelReasonByScheduleId[scheduleId] = 'hard limit';
          unawaited(_triggerCancel(scheduleId, 'hard limit'));
          continue;
        }
        final lastProgress = _lock.lastProgressAtByScheduleId[scheduleId];
        if (lastProgress != null &&
            now.difference(lastProgress) > heartbeatTimeout) {
          LoggerService.warning(
            'Watchdog: heartbeat timeout para scheduleId=$scheduleId '
            '(sem progresso ha ${now.difference(lastProgress).inMinutes}min, '
            'limite=${heartbeatTimeout.inMinutes}min)',
          );
          _lock.watchdogCancelReasonByScheduleId[scheduleId] =
              'watchdog timeout';
          unawaited(_triggerCancel(scheduleId, 'watchdog timeout'));
        }
      } on Object catch (e, st) {
        LoggerService.warning(
          'Watchdog: erro ao avaliar scheduleId=$scheduleId',
          e,
          st,
        );
      }
    }
  }

  Future<void> _triggerCancel(String scheduleId, String reason) async {
    final result = await _cancelExecution(scheduleId);
    result.fold(
      (_) => LoggerService.info(
        'Watchdog: cancel disparado para $scheduleId (reason=$reason)',
      ),
      (e) => LoggerService.warning(
        'Watchdog: falha ao cancelar $scheduleId: '
        '${failureUserMessage(e)}',
      ),
    );
  }
}
