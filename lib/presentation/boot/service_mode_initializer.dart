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
import 'package:backup_database/infrastructure/external/process/process_service.dart';
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

/// Etapas declarativas do bootstrap do modo serviço. Antes os números
/// estavam hardcoded em cada chamada `stepRunner.run(step: 1, ...)` e a
/// constante `_bootstrapTotalSteps = 11` precisava ser mantida em sincronia
/// manualmente — inserir/remover etapa exigia renumerar tudo (issue §3.3).
enum _ServiceBootstrapStep {
  init,
  loadEnv,
  detectMode,
  checkSingleInstance,
  setupDi,
  resolveServices,
  startIpc,
  initEventLog,
  setupShutdown,
  startCoreServices,
  initAutoUpdate;

  /// Index humano (1-based) usado nos labels `[N/total]`.
  int get oneBased => index + 1;
}

class ServiceModeInitializer {
  ServiceModeInitializer._();

  static const String _serviceName = WindowsServiceConstants.serviceName;
  static const Duration _fatalShutdownBackupBudget = Duration(seconds: 30);

  static Future<void> initialize() async {
    final shutdownCompleter = Completer<void>();
    final log = ServiceBootstrapLog();
    final totalSteps = _ServiceBootstrapStep.values.length;
    final stepRunner = ServiceBootstrapStepRunner(
      totalSteps: totalSteps,
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
        step: _ServiceBootstrapStep.init.oneBased,
        label: 'Iniciando ServiceModeInitializer',
        action: () async {},
      );

      await stepRunner.run(
        step: _ServiceBootstrapStep.loadEnv.oneBased,
        label: 'Carregando variaveis de ambiente',
        action: () async {
          final outcome = await EnvironmentLoader.loadIfNeeded(
            logPrefix: '[service]',
          );
          if (!outcome.dotenvInitialized) {
            LoggerService.error(
              '[service] dotenv NAO inicializado (source=${outcome.source.name},'
              ' fallback=${outcome.attemptedFallback}); features dependentes'
              ' (auto-update, single-instance) ficarao degradadas.',
              outcome.loadError ?? StateError('dotenv not initialized'),
            );
          } else if (outcome.missingRequiredKeys.isNotEmpty) {
            LoggerService.error(
              '[service] env carregado mas chaves obrigatorias ausentes: '
              '${outcome.missingRequiredKeys.toList()} '
              '(source=${outcome.source.name}, '
              'fallback=${outcome.attemptedFallback}).',
            );
          } else {
            LoggerService.info(
              '[service] env_outcome source=${outcome.source.name} '
              'keys=${outcome.loadedKeyCount} ok',
            );
          }
        },
      );

      await stepRunner.run(
        step: _ServiceBootstrapStep.detectMode.oneBased,
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
        step: _ServiceBootstrapStep.checkSingleInstance.oneBased,
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
              step: _ServiceBootstrapStep.checkSingleInstance.oneBased,
              reason: 'global_instance_lock_denied',
              exitCode: ServiceModeExitCode.lockDenied,
            );
            exit(ServiceModeExitCode.lockDenied);
          }
        },
      );

      await stepRunner.run(
        step: _ServiceBootstrapStep.setupDi.oneBased,
        label: 'Configurando dependencias (DI)',
        action: () async {
          await service_locator.setupServiceLocatorForServiceMode();
          // §2.3: o `SingleInstanceService` foi instanciado na step
          // anterior (antes do DI estar pronto) para adquirir o lock cedo.
          // Se o DI registrou uma `ISingleInstanceService` lazy (via
          // `infrastructure_module`), substituímos pelo instance que
          // realmente detém o lock — caso contrário consumidores de
          // `getIt<ISingleInstanceService>()` recebem outro objeto sem o
          // lock e o serviço pode tentar duplicar o IPC.
          final lockedInstance = singleInstanceService;
          if (lockedInstance != null) {
            if (service_locator.getIt.isRegistered<ISingleInstanceService>()) {
              await service_locator.getIt.unregister<ISingleInstanceService>();
            }
            service_locator.getIt.registerSingleton<ISingleInstanceService>(
              lockedInstance,
            );
          }
        },
      );

      await stepRunner.run(
        step: _ServiceBootstrapStep.resolveServices.oneBased,
        label: 'Obtendo servicos do container DI',
        action: () async {
          schedulerService = service_locator.getIt<ISchedulerService>();
          healthChecker = service_locator.getIt<ServiceHealthChecker>();
          eventLog = service_locator.getIt<IWindowsServiceEventLogger>();
          autoUpdateService = service_locator.getIt<AutoUpdateService>();
        },
      );

      await stepRunner.run(
        step: _ServiceBootstrapStep.startIpc.oneBased,
        label: 'Inicializando IPC do processo dono do lock',
        action: () async {
          await singleInstanceService!.startIpcServer(
            role: SingleInstanceConfig.ipcInstanceRoleService,
            onRunSchedule: ScheduledBackupExecutor.execute,
          );
        },
      );

      await stepRunner.run(
        step: _ServiceBootstrapStep.initEventLog.oneBased,
        label: 'Inicializando Event Log',
        action: () async {
          await eventLog!.initialize();
          await eventLog!.logServiceStarted();
        },
      );

      await stepRunner.run(
        step: _ServiceBootstrapStep.setupShutdown.oneBased,
        label: 'Configurando shutdown handler',
        action: () async {
          // S9: resolvido via DI em vez de singleton estático.
          shutdownHandler = service_locator.getIt<ServiceShutdownHandler>();
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
        step: _ServiceBootstrapStep.startCoreServices.oneBased,
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
        step: _ServiceBootstrapStep.initAutoUpdate.oneBased,
        label: 'Inicializando auto update do servico',
        action: () async {
          await ServiceAutoUpdateConfigurator(
            features: service_locator.getIt<FeatureAvailabilityService>(),
            autoUpdateService: autoUpdateService!,
            accountProbe: ServiceAccountProbe(
              serviceName: _serviceName,
              processService: service_locator.getIt<ProcessService>(),
            ),
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
