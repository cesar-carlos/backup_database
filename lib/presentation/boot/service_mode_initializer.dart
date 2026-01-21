import 'dart:io';
import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../core/core.dart';
import '../../core/di/service_locator.dart' as service_locator;
import '../managers/managers.dart';
import '../../application/services/scheduler_service.dart';

class ServiceModeInitializer {
  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: '.env');
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
    } catch (e, stackTrace) {
      LoggerService.error(
        'Erro fatal na inicialização do modo serviço',
        e,
        stackTrace,
      );
      try {
        await SingleInstanceService().releaseLock();
      } catch (_) {}
      exit(1);
    }
  }
}
