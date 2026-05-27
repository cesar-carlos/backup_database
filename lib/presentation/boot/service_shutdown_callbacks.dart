import 'dart:async';

import 'package:backup_database/application/services/service_health_checker.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/service/service_shutdown_handler.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_remote_staging_cleanup_scheduler.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_temporary_backup_cleanup_scheduler.dart';
import 'package:backup_database/domain/services/i_windows_service_event_logger.dart';
import 'package:backup_database/presentation/boot/service_bootstrap_log.dart';

class ServiceShutdownCallbacks {
  ServiceShutdownCallbacks({
    required this.shutdownCompleter,
    required this.schedulerServiceRef,
    required this.healthCheckerRef,
    required this.eventLogRef,
    required this.log,
  });

  static const Duration _shutdownTailBudget = Duration(seconds: 5);

  final Completer<void> shutdownCompleter;
  final ISchedulerService? Function() schedulerServiceRef;
  final ServiceHealthChecker? Function() healthCheckerRef;
  final IWindowsServiceEventLogger? Function() eventLogRef;
  final ServiceBootstrapLog log;

  void register(ServiceShutdownHandler handler) {
    handler.registerCallback(_handleShutdown);
  }

  Future<void> _handleShutdown(Duration timeout) async {
    LoggerService.info('Shutdown callback: parando servicos');
    final scheduler = schedulerServiceRef();
    final health = healthCheckerRef();
    final eventLog = eventLogRef();

    _stopIfRegistered<ITemporaryBackupCleanupScheduler>(
      'TemporaryBackupCleanupScheduler.stop',
      (instance) => instance.stop(),
    );
    _stopIfRegistered<IRemoteStagingCleanupScheduler>(
      'RemoteStagingCleanupScheduler.stop',
      (instance) => instance.stop(),
    );

    health?.stop();
    scheduler?.stop();

    final budgetForBackups = timeout > _shutdownTailBudget
        ? timeout - _shutdownTailBudget
        : timeout;

    final allCompleted =
        await scheduler?.waitForRunningBackups(timeout: budgetForBackups) ??
        false;

    if (!allCompleted) {
      LoggerService.warning(
        'Alguns backups nao terminaram a tempo, mas o servico sera encerrado',
      );
      await eventLog?.logShutdownBackupsIncomplete(
        timeout: budgetForBackups,
        details: 'Backups em execucao foram interrompidos pelo timeout.',
      );
    }

    await eventLog?.logServiceStopped();

    LoggerService.info('Shutdown callback: servicos parados');
    await log.append('shutdown callback: completed');

    _tryComplete();
  }

  void _stopIfRegistered<T extends Object>(
    String label,
    void Function(T instance) action,
  ) {
    try {
      if (service_locator.getIt.isRegistered<T>()) {
        action(service_locator.getIt<T>());
      }
    } on Object catch (e, s) {
      LoggerService.warning(
        '[ServiceShutdownCallbacks] $label: $e',
        e,
        s,
      );
    }
  }

  void _tryComplete() {
    if (shutdownCompleter.isCompleted) {
      return;
    }
    try {
      shutdownCompleter.complete();
    } on Object catch (e) {
      LoggerService.warning('[ServiceShutdownCallbacks] complete failed: $e');
    }
  }
}
