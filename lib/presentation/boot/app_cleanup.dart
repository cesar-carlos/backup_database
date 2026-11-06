import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/domain/services/i_app_database_lifecycle.dart';
import 'package:backup_database/domain/services/i_backup_cancellation_service.dart';
import 'package:backup_database/domain/services/i_execution_queue_housekeeping_scheduler.dart';
import 'package:backup_database/domain/services/i_remote_staging_cleanup_scheduler.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/domain/services/i_temporary_backup_cleanup_scheduler.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';
import 'package:backup_database/presentation/managers/managers.dart';

class AppCleanup {
  AppCleanup._();
  static final List<Future<void> Function()> _installRecovery = [];

  static Future<void> recoverFailedInstall() async {
    final actions = List<Future<void> Function()>.of(_installRecovery);
    _installRecovery.clear();
    for (final action in actions) {
      await _runStep('restaurar serviço após falha de instalação', action);
    }
  }

  /// Soft prep before launching the silent installer: stop work that
  /// would conflict with the setup, but keep the process usable if spawn
  /// fails (mutex, DB, tray and window stay up).
  static Future<void> prepareForInstall() async {
    LoggerService.info('Preparando aplicativo para instalacao...');
    _installRecovery.clear();
    final locator = service_locator.getIt;
    if (locator.isRegistered<ISchedulerService>()) {
      final scheduler = locator<ISchedulerService>();
      final wasRunning = scheduler.isRunning;
      scheduler.suspendExecutions();
      _installRecovery.add(() async {
        scheduler.resumeExecutions();
        if (wasRunning) await scheduler.start();
      });
    }
    if (locator.isRegistered<IRemoteStagingCleanupScheduler>()) {
      final cleanup = locator<IRemoteStagingCleanupScheduler>();
      if (cleanup.isRunning) _installRecovery.add(() async => cleanup.start());
    }
    if (locator.isRegistered<ITemporaryBackupCleanupScheduler>()) {
      final cleanup = locator<ITemporaryBackupCleanupScheduler>();
      if (cleanup.isRunning) _installRecovery.add(() async => cleanup.start());
    }
    if (locator.isRegistered<ConnectionManager>()) {
      final reconnect = locator<ConnectionManager>().captureReconnectAction();
      if (reconnect != null) _installRecovery.add(reconnect);
    }
    await _stopRuntimeWork();
    LoggerService.info('Preparacao para instalacao concluida');
  }

  static Future<void>? _cleanupInFlight;

  /// Keep the instance lock until producers, database and UI are stopped.
  static Future<void> cleanup({
    Duration stepTimeout = const Duration(seconds: 3),
  }) => _cleanupInFlight ??= _cleanup(stepTimeout).whenComplete(() {
    _cleanupInFlight = null;
  });

  static Future<void> _cleanup(Duration stepTimeout) async {
    _installRecovery.clear();
    WindowManagerService().beginShutdown();
    Future<void> step(String label, Future<void> Function() action) =>
        _runStep(label, action, timeout: stepTimeout);

    await step('suspender novas execuções', () async {
      if (service_locator.getIt.isRegistered<ISchedulerService>()) {
        service_locator.getIt<ISchedulerService>().suspendExecutions();
      }
    });
    await step('parar atualização automática', () async {
      if (service_locator.getIt.isRegistered<AutoUpdateService>()) {
        await service_locator.getIt<AutoUpdateService>().dispose();
      }
    });
    await step('parar servidor TCP', () async {
      if (service_locator.getIt.isRegistered<SocketServerService>()) {
        await service_locator.getIt<SocketServerService>().stop();
      }
    });
    await step('parar manutenção da fila', () async {
      if (service_locator.getIt
          .isRegistered<IExecutionQueueHousekeepingScheduler>()) {
        service_locator.getIt<IExecutionQueueHousekeepingScheduler>().stop();
      }
    });
    await _stopRuntimeWork(timeout: stepTimeout);
    await step('aguardar cancelamento dos backups', () async {
      if (service_locator.getIt.isRegistered<ISchedulerService>()) {
        await service_locator.getIt<ISchedulerService>().waitForRunningBackups(
          timeout: stepTimeout,
        );
      }
    });
    await step('fechar banco de dados', () async {
      if (service_locator.getIt.isRegistered<IAppDatabaseLifecycle>()) {
        await service_locator.getIt<IAppDatabaseLifecycle>().close();
      }
    });
    await step('destruir tray', () => TrayManagerService().dispose());
    await step(
      'destruir window manager',
      () async => WindowManagerService().dispose(),
    );
    await step('liberar lock de instância única', () async {
      if (service_locator.getIt.isRegistered<ISingleInstanceService>()) {
        await service_locator.getIt<ISingleInstanceService>().releaseLock();
      }
    });
    LoggerService.info('Aplicativo encerrado');
  }

  static Future<void> _stopRuntimeWork({Duration? timeout}) async {
    Future<void> step(String label, Future<void> Function() action) =>
        _runStep(label, action, timeout: timeout);
    await step('cancelar backups em execução', () async {
      if (service_locator.getIt.isRegistered<IBackupCancellationService>()) {
        service_locator.getIt<IBackupCancellationService>().cancelAllRunning();
      }
    });

    // §audit-2026-05-28 wave 2 (P1): desconectar do servidor antes de
    // matar o restante para garantir um fechamento limpo (heartbeat
    // parado, RPCs pendentes completados com erro, auto-reconnect
    // desativado).
    await step('desconectar do servidor remoto', () async {
      if (service_locator.getIt.isRegistered<ConnectionManager>()) {
        await service_locator.getIt<ConnectionManager>().disconnect();
      }
    });

    await step('parar scheduler', () async {
      if (service_locator.getIt.isRegistered<ISchedulerService>()) {
        service_locator.getIt<ISchedulerService>().stop();
      }
    });

    await step('parar limpeza periodica de staging remoto', () async {
      if (service_locator.getIt
          .isRegistered<IRemoteStagingCleanupScheduler>()) {
        service_locator.getIt<IRemoteStagingCleanupScheduler>().stop();
      }
    });

    await step('parar limpeza periodica de temporarios locais', () async {
      if (service_locator.getIt
          .isRegistered<ITemporaryBackupCleanupScheduler>()) {
        service_locator.getIt<ITemporaryBackupCleanupScheduler>().stop();
      }
    });
  }

  /// Executa uma etapa do shutdown isolando falhas. Etapas com [getIt]
  /// não registrado são tratadas como no-op silencioso (cenários de
  /// shutdown precoce, antes do `setupServiceLocator` completar).
  static Future<void> _runStep(
    String label,
    Future<void> Function() fn, {
    Duration? timeout,
  }) async {
    try {
      final work = Future<void>.sync(fn);
      await (timeout == null ? work : work.timeout(timeout));
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao $label: $e', e, s);
    }
  }
}
