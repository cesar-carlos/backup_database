import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/services/scheduler_service.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/presentation/managers/managers.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ServiceModeInitializer {
  static Future<void> initialize() async {
    try {
      await dotenv.load();
      LoggerService.info('Variáveis de ambiente carregadas');

      final singleInstanceService = SingleInstanceService();
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

      final schedulerService = service_locator.getIt<SchedulerService>();
      await schedulerService.start();
      LoggerService.info('✅ Serviço de agendamento iniciado em modo serviço');

      LoggerService.info('✅ Aplicativo rodando como serviço do Windows');

      await Future.delayed(const Duration(days: 365));

      await singleInstanceService.releaseLock();
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro fatal na inicialização do modo serviço',
        e,
        stackTrace,
      );
      try {
        await SingleInstanceService().releaseLock();
      } on Object catch (_) {}
      exit(1);
    }
  }
}
