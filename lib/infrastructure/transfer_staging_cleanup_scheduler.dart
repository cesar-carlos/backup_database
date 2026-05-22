import 'dart:async';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_remote_staging_cleanup_scheduler.dart';
import 'package:backup_database/domain/services/i_transfer_staging_service.dart';

/// Dispara [ITransferStagingService.cleanupOldBackups] periodicamente no
/// processo servidor (PR-4 — remocao em disco alinhada ao TTL).
class RemoteStagingCleanupScheduler implements IRemoteStagingCleanupScheduler {
  RemoteStagingCleanupScheduler(this._staging);

  final ITransferStagingService _staging;
  Timer? _timer;

  @override
  void start({
    Duration interval = const Duration(hours: 1),
  }) {
    stop();
    unawaited(_runOnce());
    _timer = Timer.periodic(interval, (_) {
      unawaited(_runOnce());
    });
    LoggerService.info(
      'RemoteStagingCleanupScheduler: intervalo=${interval.inMinutes} min',
    );
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _runOnce() async {
    try {
      await _staging.cleanupOldBackups();
    } on Object catch (e, st) {
      LoggerService.warning(
        'RemoteStagingCleanupScheduler: falha na limpeza',
        e,
        st,
      );
    }
  }
}
