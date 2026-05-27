import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/application/services/service_health_checker.dart';
import 'package:backup_database/core/config/environment_loader.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/exit_codes.dart';
import 'package:backup_database/core/service/service_shutdown_handler.dart';
import 'package:backup_database/domain/services/i_audit_retention_scheduler.dart';
import 'package:backup_database/domain/services/i_execution_queue_bootstrap.dart';
import 'package:backup_database/domain/services/i_execution_queue_housekeeping_scheduler.dart';
import 'package:backup_database/domain/services/i_file_transfer_lock_service.dart';
import 'package:backup_database/domain/services/i_remote_staging_cleanup_scheduler.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/domain/services/i_socket_server_lifecycle.dart';
import 'package:backup_database/domain/services/i_temporary_backup_cleanup_scheduler.dart';
import 'package:backup_database/domain/services/i_windows_service_event_logger.dart';
import 'package:backup_database/infrastructure/external/system/single_instance_service.dart';
import 'package:backup_database/presentation/boot/bootstrap_config.dart';
import 'package:backup_database/presentation/boot/scheduled_backup_executor.dart';
import 'package:backup_database/presentation/boot/service_account_probe.dart';
import 'package:backup_database/presentation/boot/service_auto_update_configurator.dart';
import 'package:backup_database/presentation/boot/service_bootstrap_log.dart';
import 'package:backup_database/presentation/boot/service_bootstrap_step_runner.dart';
import 'package:backup_database/presentation/boot/service_shutdown_callbacks.dart';
import 'package:backup_database/presentation/boot/socket_server_bootstrap.dart';
import 'package:flutter/foundation.dart';

class ServiceModeInitializer {
  ServiceModeInitializer._();

  static const String _serviceName = 'BackupDatabaseService';
  static const int _bootstrapTotalSteps = 11;
  static const Duration _fatalShutdownBackupBudget = Duration(seconds: 30);

  static Future<void> initialize() async {
    final shutdownCompleter = Completer<void>();
    final log = ServiceBootstrapLog();
    final stepRunner = ServiceBootstrapStepRunner(
      totalSteps: _bootstrapTotalSteps,
      log: log,
    );

    ISchedulerService? schedulerService;
    ServiceHealthChecker? healthChecker;
    IWindowsServiceEventLogger? eventLog;
    ISingleInstanceService? singleInstanceService;
    ServiceShutdownHandler? shutdownHandler;
    AutoUpdateService? autoUpdateService;

    try {
      await log.append('initialize: begin');
      LoggerService.info(
        '[bootstrap] processRole=service single_instance_mutex='
        '${SingleInstanceConfig.serviceMutexName.split(r'\').last} '
        'coexists_with_ui=independent_mutex',
      );

      await stepRunner.run(
        step: 1,
        label: 'Iniciando ServiceModeInitializer',
        action: () async {},
      );

      await stepRunner.run(
        step: 2,
        label: 'Carregando variaveis de ambiente',
        action: () => EnvironmentLoader.loadIfNeeded(logPrefix: '[service]'),
      );

      await stepRunner.run(
        step: 3,
        label: 'Detectando modo do aplicativo',
        action: () async {
          final config = BootstrapConfigResolver(
            onWarning: LoggerService.warning,
          ).resolve(rawArgs: Platform.executableArguments);
          setAppMode(config.appMode);
        },
        successDetails: () =>
            'app mode=${currentAppMode.name}, '
            'args=${Platform.executableArguments}',
      );

      await stepRunner.run(
        step: 4,
        label: 'Verificando single instance global',
        action: () async {
          singleInstanceService = SingleInstanceService();
          final isFirstServiceInstance = await singleInstanceService!
              .checkAndLock(isServiceMode: true);
          if (!isFirstServiceInstance) {
            LoggerService.warning(
              'Outra instancia do aplicativo ja esta em execucao. '
              'Encerrando servico.',
            );
            await stepRunner.markAborted(
              step: 4,
              reason: 'global_instance_lock_denied',
              exitCode: ServiceModeExitCode.lockDenied,
            );
            exit(ServiceModeExitCode.lockDenied);
          }
        },
      );

      await stepRunner.run(
        step: 5,
        label: 'Configurando dependencias (DI)',
        action: service_locator.setupServiceLocatorForServiceMode,
      );

      await stepRunner.run(
        step: 6,
        label: 'Obtendo servicos do container DI',
        action: () async {
          schedulerService = service_locator.getIt<ISchedulerService>();
          healthChecker = service_locator.getIt<ServiceHealthChecker>();
          eventLog = service_locator.getIt<IWindowsServiceEventLogger>();
          autoUpdateService = service_locator.getIt<AutoUpdateService>();
        },
      );

      await stepRunner.run(
        step: 7,
        label: 'Inicializando IPC do processo dono do lock',
        action: () async {
          await singleInstanceService!.startIpcServer(
            role: SingleInstanceConfig.ipcInstanceRoleService,
            onRunSchedule: ScheduledBackupExecutor.execute,
          );
        },
      );

      await stepRunner.run(
        step: 8,
        label: 'Inicializando Event Log',
        action: () async {
          await eventLog!.initialize();
          await eventLog!.logServiceStarted();
        },
      );

      await stepRunner.run(
        step: 9,
        label: 'Configurando shutdown handler',
        action: () async {
          shutdownHandler = ServiceShutdownHandler();
          await shutdownHandler!.initialize();
          ServiceShutdownCallbacks(
            shutdownCompleter: shutdownCompleter,
            schedulerServiceRef: () => schedulerService,
            healthCheckerRef: () => healthChecker,
            eventLogRef: () => eventLog,
            log: log,
          ).register(shutdownHandler!);
        },
      );

      await stepRunner.run(
        step: 10,
        label:
            'Iniciando scheduler, health, fila persistida e limpeza de staging',
        action: () async {
          await schedulerService!.start();
          await healthChecker!.start();
          await service_locator.getIt<IExecutionQueueBootstrap>().initialize();
          service_locator.getIt<IRemoteStagingCleanupScheduler>().start();
          service_locator.getIt<ITemporaryBackupCleanupScheduler>().start();
          // PR-6: housekeeping de TTL na fila de execucao remota.
          service_locator.getIt<IExecutionQueueHousekeepingScheduler>().start();
          // PR-6: retencao do audit log (30 dias default).
          service_locator.getIt<IAuditRetentionScheduler>().start();

          final socketLifecycle = service_locator
              .getIt<ISocketServerLifecycle>();
          await SocketServerBootstrap.ensureListening(
            isSocketServerRunning: () => socketLifecycle.isRunning,
            socketServerPort: () => socketLifecycle.port,
            cleanupExpiredFileTransferLocks: () => service_locator
                .getIt<IFileTransferLockService>()
                .cleanupExpiredLocks(),
            startSocketServer: socketLifecycle.start,
            logInfo: LoggerService.info,
          );
        },
      );

      await stepRunner.run(
        step: 11,
        label: 'Inicializando auto update do servico',
        action: () async {
          await ServiceAutoUpdateConfigurator(
            features: service_locator.getIt<FeatureAvailabilityService>(),
            autoUpdateService: autoUpdateService!,
            accountProbe: ServiceAccountProbe(serviceName: _serviceName),
            beforeInstallHook: () async {
              await shutdownHandler?.shutdown();
              await singleInstanceService?.releaseLock();
            },
          ).configureAndStart();
        },
      );

      LoggerService.info(
        'Aplicativo rodando como servico do Windows - inicializacao completa',
      );
      await log.append('initialize: complete, waiting shutdown signal');

      await shutdownCompleter.future;

      await log.append('initialize: shutdown signal received');
      await singleInstanceService?.releaseLock();
      await log.append('initialize: lock released, exiting');
    } on Object catch (e, stackTrace) {
      await _handleFatalError(
        log: log,
        completer: shutdownCompleter,
        eventLog: eventLog,
        healthChecker: healthChecker,
        schedulerService: schedulerService,
        singleInstanceService: singleInstanceService,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> _handleFatalError({
    required ServiceBootstrapLog log,
    required Completer<void> completer,
    required IWindowsServiceEventLogger? eventLog,
    required ServiceHealthChecker? healthChecker,
    required ISchedulerService? schedulerService,
    required ISingleInstanceService? singleInstanceService,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    LoggerService.error(
      'Erro fatal na inicializacao do modo servico',
      error,
      stackTrace,
    );
    await log.append(
      'initialize: fatal error',
      error: error,
      stackTrace: stackTrace,
    );

    try {
      await eventLog?.logCriticalError(
        error: error.toString(),
        context: 'Erro fatal na inicializacao do modo servico',
      );
    } on Object catch (_) {}

    try {
      healthChecker?.stop();
    } on Object catch (failure, stack) {
      LoggerService.warning('Erro ao parar health checker', failure, stack);
    }

    try {
      await schedulerService?.waitForRunningBackups(
        timeout: _fatalShutdownBackupBudget,
      );
    } on Object catch (failure, stack) {
      LoggerService.warning(
        'Erro ao aguardar backups terminarem',
        failure,
        stack,
      );
    }

    try {
      await singleInstanceService?.releaseLock();
    } on Object catch (failure, stack) {
      LoggerService.warning(
        'Erro ao liberar lock antes de encerrar modo servico',
        failure,
        stack,
      );
    }

    _tryCompleteError(completer, error);

    await log.append(
      'initialize: exiting process with code '
      '${ServiceModeExitCode.fatalBootstrapError}',
    );
    exit(ServiceModeExitCode.fatalBootstrapError);
  }

  @visibleForTesting
  static String? buildUnsupportedServiceAccountMessage(
    String? serviceAccount,
  ) => ServiceAccountProbe.buildUnsupportedServiceAccountMessage(
    serviceAccount,
  );

  @visibleForTesting
  static bool isSupportedSilentUpdateServiceAccount(
    String? serviceAccount,
  ) => ServiceAccountProbe.isSupportedSilentUpdateServiceAccount(
    serviceAccount,
  );

  static void _tryCompleteError(Completer<void> completer, Object error) {
    if (completer.isCompleted) {
      return;
    }
    try {
      completer.completeError(error);
    } on Object catch (err) {
      LoggerService.warning(
        '[ServiceModeInitializer] completeError failed: $err',
      );
    }
  }
}
