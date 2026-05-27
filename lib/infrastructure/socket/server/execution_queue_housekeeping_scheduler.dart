import 'dart:async';

import 'package:backup_database/core/constants/backup_constants.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_execution_queue_housekeeping_scheduler.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_service.dart';

/// PR-6: housekeeping periodico da fila de execucao remota. Dispara
/// `ExecutionQueueService.pruneExpired` a cada
/// `BackupConstants.queueHousekeepingInterval`.
///
/// Inicializado no `ServiceModeInitializer` step 10, junto com o
/// `RemoteStagingCleanupScheduler`. Em modo UI (cliente), nao e
/// necessario rodar — a fila so existe no servidor.
class ExecutionQueueHousekeepingScheduler
    implements IExecutionQueueHousekeepingScheduler {
  ExecutionQueueHousekeepingScheduler(
    this._queueService, {
    Duration? interval,
  }) : _interval = interval ?? BackupConstants.queueHousekeepingInterval;

  final ExecutionQueueService _queueService;
  final Duration _interval;

  Timer? _timer;

  @override
  void start() {
    if (_timer != null) return;
    LoggerService.info(
      'ExecutionQueueHousekeepingScheduler: intervalo='
      '${_interval.inSeconds}s',
    );
    _timer = Timer.periodic(_interval, (_) => unawaited(_tick()));
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    try {
      final expired = await _queueService.pruneExpired();
      if (expired.isNotEmpty) {
        LoggerService.info(
          'Fila: ${expired.length} item(s) expiraram por TTL e foram '
          'removidos (runIds=${expired.map((e) => e.runId).join(", ")}).',
        );
      }
    } on Object catch (e, st) {
      LoggerService.warning(
        'ExecutionQueueHousekeepingScheduler: erro no tick',
        e,
        st,
      );
    }
  }
}
