import '../../core/core.dart';
import '../../core/di/service_locator.dart' as service_locator;
import '../../application/services/scheduler_service.dart';
import '../managers/managers.dart';

class AppCleanup {
  static Future<void> cleanup() async {
    LoggerService.info('Encerrando aplicativo...');

    try {
      service_locator.getIt<SchedulerService>().stop();
    } catch (e) {
      LoggerService.warning('Erro ao parar scheduler: $e');
    }

    await SingleInstanceService().releaseLock();

    try {
      TrayManagerService().dispose();
    } catch (e) {
      LoggerService.warning('Erro ao destruir tray: $e');
    }

    try {
      WindowManagerService().dispose();
    } catch (e) {
      LoggerService.warning('Erro ao destruir window manager: $e');
    }

    LoggerService.info('Aplicativo encerrado');
  }
}
