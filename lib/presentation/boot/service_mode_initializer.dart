import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/services/service_health_checker.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/service/service_shutdown_handler.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/infrastructure/external/system/system.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
      LoggerService.info('>>> [1/8] Iniciando ServiceModeInitializer');
      await _appendBootstrapLog('step 1/8: ServiceModeInitializer started');

      try {
        await dotenv.load();
        LoggerService.info('>>> [2/8] Variáveis de ambiente carregadas');
        await _appendBootstrapLog('step 2/8: dotenv loaded');
      } on Object catch (e) {
        LoggerService.warning(
          '>>> [2/8] Arquivo .env não encontrado ou inválido: $e. '
          'O serviço continuará com configurações padrão. '
          'Copie .env.example para .env na pasta do aplicativo se necessário.',
        );
        await _appendBootstrapLog(
          'step 2/8: dotenv load failed, continuing',
          e,
        );
      }

      setAppMode(getAppMode(Platform.executableArguments));
      LoggerService.info(
        '>>> [3/8] Modo do aplicativo (servico): ${currentAppMode.name}',
      );
      await _appendBootstrapLog(
        'step 3/8: app mode=${currentAppMode.name}, '
        'args=${Platform.executableArguments}',
      );

      LoggerService.info('>>> [4/8] Verificando single instance...');
      singleInstanceService = SingleInstanceService();
      final isFirstServiceInstance = await singleInstanceService.checkAndLock(
        isServiceMode: true,
      );
      LoggerService.info(
        '>>> [4/8] Single instance check realizado para modo serviço',
      );
      await _appendBootstrapLog(
        'step 4/8: single instance result=$isFirstServiceInstance',
      );

      if (!isFirstServiceInstance) {
        LoggerService.warning(
          '⚠️ Outra instância do SERVIÇO já está em execução. Encerrando.',
        );
        await _appendBootstrapLog(
          'step 4/8: existing service instance found, exiting 0',
        );
        exit(0);
      }

      LoggerService.info('>>> [5/8] Configurando dependências...');
      await _appendBootstrapLog('step 5/8: setupServiceLocator begin');
      await service_locator.setupServiceLocatorForServiceMode();
      LoggerService.info('>>> [5/8] Dependências configuradas com sucesso');
      await _appendBootstrapLog('step 5/8: setupServiceLocator success');

      LoggerService.info('>>> [6/8] Obtendo serviços do container DI...');
      schedulerService = service_locator.getIt<ISchedulerService>();
      healthChecker = service_locator.getIt<ServiceHealthChecker>();
      eventLog = service_locator.getIt<WindowsEventLogService>();
      LoggerService.info('>>> [6/8] Serviços obtidos com sucesso');
      await _appendBootstrapLog('step 6/8: getIt services success');

      // Inicializa Windows Event Log
      LoggerService.info('>>> [7/8] Inicializando Event Log...');
      await _appendBootstrapLog('step 7/8: eventLog.initialize begin');
      await eventLog.initialize();
      await eventLog.logServiceStarted();
      LoggerService.info('>>> [7/8] Event Log inicializado');
      await _appendBootstrapLog('step 7/8: eventLog initialized');

      // Inicializa graceful shutdown handler
      LoggerService.info('>>> [7/8] Configurando shutdown handler...');
      final shutdownHandler = ServiceShutdownHandler();
      await shutdownHandler.initialize();
      LoggerService.info('>>> [7/8] Shutdown handler configurado');
      await _appendBootstrapLog('step 7/8: shutdown handler initialized');

      // Registra callback de shutdown
      shutdownHandler.registerCallback((timeout) async {
        LoggerService.info('🛑 Shutdown callback: Parando serviços');

        // Para health checker primeiro
        healthChecker?.stop();

        // Para de aceitar novos schedules
        schedulerService?.stop();

        // Aguarda backups em execução terminarem respeitando o timeout do SCM
        final budgetForBackups = timeout > const Duration(seconds: 5)
            ? timeout - const Duration(seconds: 5)
            : timeout;

        final allCompleted =
            await schedulerService?.waitForRunningBackups(
              timeout: budgetForBackups,
            ) ??
            false;

        if (!allCompleted) {
          LoggerService.warning(
            '⚠️ Alguns backups não terminaram a tempo, '
            'mas o serviço será encerrado',
          );
          await eventLog?.logShutdownBackupsIncomplete(
            timeout: budgetForBackups,
            details: 'Backups em execução foram interrompidos pelo timeout.',
          );
        }

        // Log no Event Viewer
        await eventLog?.logServiceStopped();

        LoggerService.info('✅ Shutdown callback: Serviços parados');
        await _appendBootstrapLog('shutdown callback: completed');

        // Signal the main wait loop that shutdown is done.
        _tryComplete(shutdownCompleter);
      });

      LoggerService.info('>>> [8/8] Iniciando scheduler...');
      await _appendBootstrapLog('step 8/8: scheduler.start begin');
      await schedulerService.start();
      LoggerService.info('>>> [8/8] ✅ Serviço de agendamento iniciado');
      await _appendBootstrapLog('step 8/8: scheduler.start success');

      // Inicia health checker
      LoggerService.info('>>> [8/8] Iniciando health checker...');
      await _appendBootstrapLog('step 8/8: healthChecker.start begin');
      await healthChecker.start();
      LoggerService.info('>>> [8/8] ✅ Verificador de saúde iniciado');
      await _appendBootstrapLog('step 8/8: healthChecker.start success');

      LoggerService.info(
        '🎉 ✅ Aplicativo rodando como serviço do Windows - INICIALIZAÇÃO COMPLETA',
      );
      await _appendBootstrapLog(
        'initialize: complete, waiting shutdown signal',
      );

      // Aguarda indefinidamente (será interrompido por shutdown signal via Completer)
      await shutdownCompleter.future;

      await _appendBootstrapLog('initialize: shutdown signal received');
      await singleInstanceService.releaseLock();
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
        if (schedulerService != null) {
          await schedulerService.waitForRunningBackups(
            timeout: const Duration(seconds: 30),
          );
        }
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
    } on Object {
      // Intentionally swallow bootstrap logging failures.
    }
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
