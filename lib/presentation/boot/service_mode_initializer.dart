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

  static Future<void> initialize() async {
    final shutdownCompleter = Completer<void>();
    ISchedulerService? schedulerService;
    ServiceHealthChecker? healthChecker;
    WindowsEventLogService? eventLog;
    ISingleInstanceService? singleInstanceService;

    try {
      await dotenv.load();
      setAppMode(getAppMode(Platform.executableArguments));
      LoggerService.info(
        'Modo do aplicativo (servico): ${currentAppMode.name}',
      );
      LoggerService.info('Variáveis de ambiente carregadas');

      singleInstanceService = SingleInstanceService();
      final isFirstServiceInstance = await singleInstanceService.checkAndLock(
        isServiceMode: true,
      );
      LoggerService.info('Single instance check realizado para modo serviço');

      if (!isFirstServiceInstance) {
        LoggerService.warning(
          '⚠️ Outra instância do SERVIÇO já está em execução. Encerrando.',
        );
        exit(0);
      }

      await service_locator.setupServiceLocator();
      LoggerService.info('Dependências configuradas');

      schedulerService = service_locator.getIt<ISchedulerService>();
      healthChecker = service_locator.getIt<ServiceHealthChecker>();
      eventLog = service_locator.getIt<WindowsEventLogService>();

      // Inicializa Windows Event Log
      await eventLog.initialize();
      await eventLog.logServiceStarted();

      // Inicializa graceful shutdown handler
      final shutdownHandler = ServiceShutdownHandler();
      await shutdownHandler.initialize();

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
        }

        // Log no Event Viewer
        await eventLog?.logServiceStopped();

        LoggerService.info('✅ Shutdown callback: Serviços parados');

        // Completa o Future para encerrar o serviço
        if (!shutdownCompleter.isCompleted) {
          shutdownCompleter.complete();
        }
      });

      await schedulerService.start();
      LoggerService.info('✅ Serviço de agendamento iniciado em modo serviço');

      // Inicia health checker
      await healthChecker.start();
      LoggerService.info('✅ Verificador de saúde iniciado');

      LoggerService.info('✅ Aplicativo rodando como serviço do Windows');

      // Aguarda indefinidamente (será interrompido por shutdown signal via Completer)
      await shutdownCompleter.future;

      await singleInstanceService.releaseLock();
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro fatal na inicialização do modo serviço',
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

      // Completa o Future em caso de erro fatal
      if (!shutdownCompleter.isCompleted) {
        shutdownCompleter.completeError(e);
      }

      exit(1);
    }
  }
}
