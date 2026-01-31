import 'package:backup_database/application/services/scheduler_service.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/presentation/managers/managers.dart';

class AppCleanup {
  static Future<void> cleanup() async {
    LoggerService.info('Encerrando aplicativo...');

    try {
      service_locator.getIt<SchedulerService>().stop();
    } on Object catch (e) {
      LoggerService.warning('Erro ao parar scheduler: $e');
    }

    await SingleInstanceService().releaseLock();

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
