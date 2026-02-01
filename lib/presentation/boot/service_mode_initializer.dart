import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/services/scheduler_service.dart';
import 'package:backup_database/application/services/service_health_checker.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/service/service_shutdown_handler.dart';
import 'package:backup_database/infrastructure/external/system/system.dart';
import 'package:backup_database/presentation/managers/managers.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ServiceModeInitializer {
  static Future<void> initialize() async {
    SchedulerService? schedulerService;
    ServiceHealthChecker? healthChecker;
    WindowsEventLogService? eventLog;
    SingleInstanceService? singleInstanceService;

    try {
      await dotenv.load();
      LoggerService.info('Variáveis de ambiente carregadas');

      singleInstanceService = SingleInstanceService();
      final isFirstServiceInstance = await singleInstanceService.checkAndLock(
        isServiceMode: true,
      );

      if (!isFirstServiceInstance) {
        LoggerService.warning(
          '⚠️ Outra instância do SERVIÇO já está em execução. Encerrando.',
        );
        exit(0);
      }

      await service_locator.setupServiceLocator();
      LoggerService.info('Dependências configuradas');

      schedulerService = service_locator.getIt<SchedulerService>();
      healthChecker = service_locator.getIt<ServiceHealthChecker>();
      eventLog = service_locator.getIt<WindowsEventLogService>();

      // Inicializa Windows Event Log
      await eventLog.initialize();
      await eventLog.logServiceStarted();

      // Inicializa graceful shutdown handler
      await ServiceShutdownHandler.instance.initialize();

      // Registra callback de shutdown
      ServiceShutdownHandler.instance.registerCallback((timeout) async {
        LoggerService.info('🛑 Shutdown callback: Parando serviços');

        // Para health checker primeiro
        healthChecker?.stop();

        // Para de aceitar novos schedules
        schedulerService?.stop();

        // Aguarda backups em execução terminarem
        final allCompleted =
            await schedulerService?.waitForRunningBackups() ?? false;

        if (!allCompleted) {
          LoggerService.warning(
            '⚠️ Alguns backups não terminaram a tempo, '
            'mas o serviço será encerrado',
          );
        }

        // Log no Event Viewer
        await eventLog?.logServiceStopped();

        LoggerService.info('✅ Shutdown callback: Serviços parados');
      });

      await schedulerService.start();
      LoggerService.info('✅ Serviço de agendamento iniciado em modo serviço');

      // Inicia health checker
      await healthChecker.start();
      LoggerService.info('✅ Verificador de saúde iniciado');

      LoggerService.info('✅ Aplicativo rodando como serviço do Windows');

      // Aguarda indefinidamente (será interrompido por shutdown signal)
      await Future.delayed(const Duration(days: 365));

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
      exit(1);
    }
  }
}
