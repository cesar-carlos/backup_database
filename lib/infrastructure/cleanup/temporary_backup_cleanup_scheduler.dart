import 'dart:async';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_temporary_backup_cleanup_scheduler.dart';
import 'package:backup_database/domain/services/i_temporary_backup_cleanup_service.dart';

class TemporaryBackupCleanupScheduler
    implements ITemporaryBackupCleanupScheduler {
  TemporaryBackupCleanupScheduler(this._cleanupService);

  final ITemporaryBackupCleanupService _cleanupService;
  Timer? _timer;

  @override
  void start({Duration interval = const Duration(hours: 1)}) {
    stop();
    unawaited(_runOnce());
    _timer = Timer.periodic(interval, (_) {
      unawaited(_runOnce());
    });
    LoggerService.info(
      'TemporaryBackupCleanupScheduler: intervalo=${interval.inMinutes} min',
    );
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _runOnce() async {
    try {
      await _cleanupService.cleanupOrphanedFailedUploads();
    } on Object catch (e, st) {
      LoggerService.warning(
        'TemporaryBackupCleanupScheduler: falha na limpeza',
        e,
        st,
      );
    }
  }
}
