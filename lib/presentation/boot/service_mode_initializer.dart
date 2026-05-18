import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/application/services/service_health_checker.dart';
import 'package:backup_database/core/config/environment_loader.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/service/service_shutdown_handler.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/infrastructure/external/system/system.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_service.dart';
import 'package:backup_database/infrastructure/transfer_staging_cleanup_scheduler.dart';

class ServiceModeInitializer {
  ServiceModeInitializer._();

  static const String _defaultProgramData = r'C:\ProgramData';
  static const String _bootstrapLogRelativePath =
      r'BackupDatabase\logs\service_bootstrap.log';

  static Future<void> initialize() async {
    final shutdownCompleter = Completer<void>();
    ISchedulerService? schedulerService;
    ServiceHealthChecker? healthChecker;
    WindowsEventLogService? eventLog;
    ISingleInstanceService? singleInstanceService;
    ServiceShutdownHandler? shutdownHandler;
    AutoUpdateService? autoUpdateService;

    try {
      await _appendBootstrapLog('initialize: begin');
      LoggerService.info(
        '[bootstrap] processRole=service single_instance_mutex='
        '${SingleInstanceConfig.serviceMutexName.split(r'\').last} '
        'coexists_with_ui=independent_mutex',
      );
      const totalSteps = 10;

      await _bootstrapStep(
        step: 1,
        totalSteps: totalSteps,
        label: 'Iniciando ServiceModeInitializer',
        action: () async {},
      );

      await _bootstrapStep(
        step: 2,
        totalSteps: totalSteps,
        label: 'Carregando variaveis de ambiente',
        action: () => EnvironmentLoader.loadIfNeeded(logPrefix: '[service]'),
      );

      await _bootstrapStep(
        step: 3,
        totalSteps: totalSteps,
        label: 'Detectando modo do aplicativo',
        action: () async {
          setAppMode(getAppMode(Platform.executableArguments));
        },
        successDetails: () =>
            'app mode=${currentAppMode.name}, '
            'args=${Platform.executableArguments}',
      );

      await _bootstrapStep(
        step: 4,
        totalSteps: totalSteps,
        label: 'Verificando single instance',
        action: () async {
          singleInstanceService = SingleInstanceService();
          final isFirstServiceInstance = await singleInstanceService!
              .checkAndLock(isServiceMode: true);
          if (!isFirstServiceInstance) {
            LoggerService.warning(
              'Outra instancia do servico ja esta em execucao. Encerrando.',
            );
            await _appendBootstrapLog(
              'step 4/$totalSteps: existing service instance found, exiting 0',
            );
            exit(0);
          }
        },
      );

      await _bootstrapStep(
        step: 5,
        totalSteps: totalSteps,
        label: 'Configurando dependencias (DI)',
        action: service_locator.setupServiceLocatorForServiceMode,
      );

      await _bootstrapStep(
        step: 6,
        totalSteps: totalSteps,
        label: 'Obtendo servicos do container DI',
        action: () async {
          schedulerService = service_locator.getIt<ISchedulerService>();
          healthChecker = service_locator.getIt<ServiceHealthChecker>();
          eventLog = service_locator.getIt<WindowsEventLogService>();
          autoUpdateService = service_locator.getIt<AutoUpdateService>();
        },
      );

      await _bootstrapStep(
        step: 7,
        totalSteps: totalSteps,
        label: 'Inicializando Event Log',
        action: () async {
          await eventLog!.initialize();
          await eventLog!.logServiceStarted();
        },
      );

      await _bootstrapStep(
        step: 8,
        totalSteps: totalSteps,
        label: 'Configurando shutdown handler',
        action: () async {
          shutdownHandler = ServiceShutdownHandler();
          await shutdownHandler!.initialize();
          _registerShutdownCallbacks(
            shutdownHandler: shutdownHandler!,
            shutdownCompleter: shutdownCompleter,
            schedulerServiceRef: () => schedulerService,
            healthCheckerRef: () => healthChecker,
            eventLogRef: () => eventLog,
          );
        },
      );

      await _bootstrapStep(
        step: 9,
        totalSteps: totalSteps,
        label:
            'Iniciando scheduler, health, fila persistida e limpeza de staging',
        action: () async {
          await schedulerService!.start();
          await healthChecker!.start();
          await service_locator.getIt<ExecutionQueueService>().initialize();
          service_locator.getIt<RemoteStagingCleanupScheduler>().start();
        },
      );

      await _bootstrapStep(
        step: 10,
        totalSteps: totalSteps,
        label: 'Inicializando auto update do servico',
        action: () async {
          final features = service_locator.getIt<FeatureAvailabilityService>();
          if (!features.isAutoUpdateEnabled) {
            LoggerService.info(
              'AutoUpdateService omitido no servico (compatibilidade): '
              '${features.autoUpdateDisabledReason?.diagnosticLabel ?? "unknown"}',
            );
            return;
          }

          autoUpdateService!.setBeforeInstallHook(() async {
            await shutdownHandler?.shutdown();
            await singleInstanceService?.releaseLock();
          });
          await autoUpdateService!.initialize();
          if (!autoUpdateService!.isInitialized) {
            LoggerService.info(
              'AutoUpdateService em modo servico ficou desabilitado/sem feed',
            );
            return;
          }
          autoUpdateService!.startPeriodicChecks();
          unawaited(
            autoUpdateService!.checkNow(source: AppUpdateSource.startup),
          );
        },
      );

      LoggerService.info(
        'Aplicativo rodando como servico do Windows - inicializacao completa',
      );
      await _appendBootstrapLog(
        'initialize: complete, waiting shutdown signal',
      );

      await shutdownCompleter.future;

      await _appendBootstrapLog('initialize: shutdown signal received');
      await singleInstanceService?.releaseLock();
      await _appendBootstrapLog('initialize: lock released, exiting');
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro fatal na inicializacao do modo servico',
        e,
        stackTrace,
      );
      await _appendBootstrapLog(
        'initialize: fatal error',
        e,
        stackTrace,
      );

      try {
        await eventLog?.logCriticalError(
          error: e.toString(),
          context: 'Erro fatal na inicializacao do modo servico',
        );
      } on Object catch (_) {}

      try {
        healthChecker?.stop();
      } on Object catch (error, stack) {
        LoggerService.warning('Erro ao parar health checker', error, stack);
      }

      try {
        await schedulerService?.waitForRunningBackups(
          timeout: const Duration(seconds: 30),
        );
      } on Object catch (error, stack) {
        LoggerService.warning(
          'Erro ao aguardar backups terminarem',
          error,
          stack,
        );
      }

      try {
        await singleInstanceService?.releaseLock();
      } on Object catch (error, stack) {
        LoggerService.warning(
          'Erro ao liberar lock antes de encerrar modo servico',
          error,
          stack,
        );
      }

      _tryCompleteError(shutdownCompleter, e);

      await _appendBootstrapLog('initialize: exiting process with code 1');
      exit(1);
    }
  }

  static String _getBootstrapLogPath() {
    final programData =
        Platform.environment['ProgramData'] ?? _defaultProgramData;
    return '$programData\\$_bootstrapLogRelativePath';
  }

  static Future<void> _appendBootstrapLog(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) async {
    try {
      final logPath = _getBootstrapLogPath();
      final file = File(logPath);
      await file.parent.create(recursive: true);
      final now = DateTime.now().toIso8601String();
      final buffer = StringBuffer('[$now] $message');
      if (error != null) {
        buffer.write('\nerror: $error');
      }
      if (stackTrace != null) {
        buffer.write('\nstack: $stackTrace');
      }
      buffer.write('\n');
      await file.writeAsString(buffer.toString(), mode: FileMode.append);
    } on Object catch (e) {
      developer.log(
        '[ServiceModeInitializer] bootstrap log write failed: $e',
        name: 'service_bootstrap',
        level: 1000,
      );
    }
  }

  static Future<void> _bootstrapStep({
    required int step,
    required int totalSteps,
    required String label,
    required Future<void> Function() action,
    String Function()? successDetails,
  }) async {
    final tag = '[$step/$totalSteps]';
    LoggerService.info('>>> $tag $label...');
    await _appendBootstrapLog('step $step/$totalSteps: $label begin');
    try {
      await action();
      final details = successDetails?.call();
      LoggerService.info('>>> $tag OK $label');
      await _appendBootstrapLog(
        'step $step/$totalSteps: $label success'
        '${details != null ? ' ($details)' : ''}',
      );
    } on Object catch (e, s) {
      await _appendBootstrapLog(
        'step $step/$totalSteps: $label failed',
        e,
        s,
      );
      rethrow;
    }
  }

  static void _registerShutdownCallbacks({
    required ServiceShutdownHandler shutdownHandler,
    required Completer<void> shutdownCompleter,
    required ISchedulerService? Function() schedulerServiceRef,
    required ServiceHealthChecker? Function() healthCheckerRef,
    required WindowsEventLogService? Function() eventLogRef,
  }) {
    shutdownHandler.registerCallback((timeout) async {
      LoggerService.info('Shutdown callback: parando servicos');
      final scheduler = schedulerServiceRef();
      final health = healthCheckerRef();
      final eventLog = eventLogRef();

      try {
        if (service_locator.getIt
            .isRegistered<RemoteStagingCleanupScheduler>()) {
          service_locator.getIt<RemoteStagingCleanupScheduler>().stop();
        }
      } on Object catch (e, s) {
        LoggerService.warning(
          '[ServiceModeInitializer] RemoteStagingCleanupScheduler.stop: $e',
          e,
          s,
        );
      }

      health?.stop();
      scheduler?.stop();

      final budgetForBackups = timeout > const Duration(seconds: 5)
          ? timeout - const Duration(seconds: 5)
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
      await _appendBootstrapLog('shutdown callback: completed');

      _tryComplete(shutdownCompleter);
    });
  }

  static void _tryComplete(Completer<void> completer) {
    if (!completer.isCompleted) {
      try {
        completer.complete();
      } on Object catch (e) {
        LoggerService.warning('[ServiceModeInitializer] complete failed: $e');
      }
    }
  }

  static void _tryCompleteError(Completer<void> completer, Object error) {
    if (!completer.isCompleted) {
      try {
        completer.completeError(error);
      } on Object catch (err) {
        LoggerService.warning(
          '[ServiceModeInitializer] completeError failed: $err',
        );
      }
    }
  }
}
