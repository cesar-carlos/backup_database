import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/presentation/managers/managers.dart';

class AppCleanup {
  AppCleanup._();

  static Future<void> cleanup() async {
    LoggerService.info('Encerrando aplicativo...');

    try {
      service_locator.getIt<ISchedulerService>().stop();
    } on Object catch (e) {
      LoggerService.warning('Erro ao parar scheduler: $e');
    }

    try {
      final singleInstanceService = service_locator
          .getIt<ISingleInstanceService>();
      await singleInstanceService.releaseLock();
    } on Object catch (e) {
      LoggerService.warning('Erro ao liberar lock de instância única: $e');
    }

    try {
      TrayManagerService().dispose();
    } on Object catch (e) {
      LoggerService.warning('Erro ao destruir tray: $e');
    }

    try {
      WindowManagerService().dispose();
    } on Object catch (e) {
      LoggerService.warning('Erro ao destruir window manager: $e');
    }

    LoggerService.info('Aplicativo encerrado');
  }
}
