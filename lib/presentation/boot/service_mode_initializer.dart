import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

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

    try {
      await _appendBootstrapLog('initialize: begin');
      LoggerService.info(
        '[bootstrap] processRole=service single_instance_mutex='
        '${SingleInstanceConfig.serviceMutexName.split(r'\').last} '
        'coexists_with_ui=independent_mutex',
      );
      const totalSteps = 9;

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
              '⚠️ Outra instância do SERVIÇO já está em execução. Encerrando.',
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
        label: 'Configurando dependências (DI)',
        action: service_locator.setupServiceLocatorForServiceMode,
      );

      await _bootstrapStep(
        step: 6,
        totalSteps: totalSteps,
        label: 'Obtendo serviços do container DI',
        action: () async {
          schedulerService = service_locator.getIt<ISchedulerService>();
          healthChecker = service_locator.getIt<ServiceHealthChecker>();
          eventLog = service_locator.getIt<WindowsEventLogService>();
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

      // Inicializa graceful shutdown handler (passo 8)
      await _bootstrapStep(
        step: 8,
        totalSteps: totalSteps,
        label: 'Configurando shutdown handler',
        action: () async {
          final shutdownHandler = ServiceShutdownHandler();
          await shutdownHandler.initialize();
          _registerShutdownCallbacks(
            shutdownHandler: shutdownHandler,
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
        label: 'Iniciando scheduler, health, fila persistida e limpeza de staging',
        action: () async {
          await schedulerService!.start();
          await healthChecker!.start();
          await service_locator.getIt<ExecutionQueueService>().initialize();
          service_locator.getIt<RemoteStagingCleanupScheduler>().start();
        },
      );

      LoggerService.info(
        '🎉 ✅ Aplicativo rodando como serviço do Windows - INICIALIZAÇÃO COMPLETA',
      );
      await _appendBootstrapLog(
        'initialize: complete, waiting shutdown signal',
      );

      // Aguarda indefinidamente (será interrompido por shutdown signal via Completer)
      await shutdownCompleter.future;

      await _appendBootstrapLog('initialize: shutdown signal received');
      await singleInstanceService?.releaseLock();
      await _appendBootstrapLog('initialize: lock released, exiting');
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro fatal na inicialização do modo serviço',
        e,
        stackTrace,
      );
      await _appendBootstrapLog(
        'initialize: fatal error',
        e,
        stackTrace,
      );

      // Log erro crítico no Event Viewer
      try {
        await eventLog?.logCriticalError(
          error: e.toString(),
          context: 'Erro fatal na inicialização do modo serviço',
        );
      } on Object catch (_) {}

      try {
        // Para health checker
        healthChecker?.stop();
      } on Object catch (e, s) {
        LoggerService.warning('Erro ao parar health checker', e, s);
      }

      try {
        // Tenta parar o scheduler gracefulmente
        await schedulerService?.waitForRunningBackups(
          timeout: const Duration(seconds: 30),
        );
      } on Object catch (e, s) {
        LoggerService.warning('Erro ao aguardar backups terminarem', e, s);
      }

      try {
        await singleInstanceService?.releaseLock();
      } on Object catch (e, s) {
        LoggerService.warning(
          'Erro ao liberar lock antes de encerrar modo serviço',
          e,
          s,
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
      // Antes este catch ficava completamente silencioso, escondendo
      // permission denied / disk full em produção. Agora ao menos
      // emite no console de developer (não vai para o LoggerService
      // para evitar loop caso o próprio LoggerService falhe na escrita).
      developer.log(
        '[ServiceModeInitializer] bootstrap log write failed: $e',
        name: 'service_bootstrap',
        level: 1000,
      );
    }
  }

  /// Helper genérico para um passo da inicialização do serviço. Encapsula
  /// o padrão repetido de:
  ///  - log "[step/total] <label>"
  ///  - escrever no bootstrap log file
  ///  - executar a ação
  ///  - log de sucesso (ou propagar exceção)
  ///
  /// Centralizar elimina ~60 linhas de código repetido e garante
  /// numeração consistente dos passos.
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
      LoggerService.info('>>> $tag ✅ $label');
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

  /// Registra os callbacks de shutdown do `ServiceShutdownHandler`. Extraído
  /// para fora do método principal para reduzir o tamanho do
  /// `initialize()` e isolar a lógica do shutdown gracioso.
  static void _registerShutdownCallbacks({
    required ServiceShutdownHandler shutdownHandler,
    required Completer<void> shutdownCompleter,
    required ISchedulerService? Function() schedulerServiceRef,
    required ServiceHealthChecker? Function() healthCheckerRef,
    required WindowsEventLogService? Function() eventLogRef,
  }) {
    shutdownHandler.registerCallback((timeout) async {
      LoggerService.info('🛑 Shutdown callback: Parando serviços');
      final scheduler = schedulerServiceRef();
      final health = healthCheckerRef();
      final eventLog = eventLogRef();

      try {
        if (service_locator.getIt.isRegistered<RemoteStagingCleanupScheduler>()) {
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

      // Reserva 5s do orçamento total para fechar caches/EventLog/etc.
      final budgetForBackups = timeout > const Duration(seconds: 5)
          ? timeout - const Duration(seconds: 5)
          : timeout;

      final allCompleted =
          await scheduler?.waitForRunningBackups(timeout: budgetForBackups) ??
          false;

      if (!allCompleted) {
        LoggerService.warning(
          '⚠️ Alguns backups não terminaram a tempo, mas o serviço será '
          'encerrado',
        );
        await eventLog?.logShutdownBackupsIncomplete(
          timeout: budgetForBackups,
          details: 'Backups em execução foram interrompidos pelo timeout.',
        );
      }

      await eventLog?.logServiceStopped();

      LoggerService.info('✅ Shutdown callback: Serviços parados');
      await _appendBootstrapLog('shutdown callback: completed');

      _tryComplete(shutdownCompleter);
    });
  }

  /// Completes [c] if it is not already completed.
  /// Guards against double-complete StateErrors during concurrent signals.
  static void _tryComplete(Completer<void> c) {
    if (!c.isCompleted) {
      try {
        c.complete();
      } on Object catch (e) {
        LoggerService.warning('[ServiceModeInitializer] complete failed: $e');
      }
    }
  }

  static void _tryCompleteError(Completer<void> c, Object e) {
    if (!c.isCompleted) {
      try {
        c.completeError(e);
      } on Object catch (err) {
        LoggerService.warning(
          '[ServiceModeInitializer] completeError failed: $err',
        );
      }
    }
  }
}
