import 'dart:io';

import '../../core/core.dart';
import '../../core/di/service_locator.dart' as service_locator;
import '../managers/managers.dart';
import '../boot/app_cleanup.dart';
import '../../application/services/scheduler_service.dart';
import '../../domain/repositories/repositories.dart';

class TrayMenuHandler {
  static void handleAction(TrayMenuAction action) {
    switch (action) {
      case TrayMenuAction.show:
        WindowManagerService().show();
        break;

      case TrayMenuAction.executeBackup:
        _executeManualBackup();
        break;

      case TrayMenuAction.pauseScheduler:
        service_locator.getIt<SchedulerService>().stop();
        TrayManagerService().setSchedulerPaused(true);
        break;

      case TrayMenuAction.resumeScheduler:
        service_locator.getIt<SchedulerService>().start();
        TrayManagerService().setSchedulerPaused(false);
        break;

      case TrayMenuAction.settings:
        _navigateToSettings();
        break;

      case TrayMenuAction.exit:
        _exitApp();
        break;
    }
  }

  static Future<void> _executeManualBackup() async {
    LoggerService.info('Executar backup manual solicitado via tray');

    try {
      final scheduleRepository = service_locator.getIt<IScheduleRepository>();
      final schedulerService = service_locator.getIt<SchedulerService>();

      final schedulesResult = await scheduleRepository.getEnabled();

      await schedulesResult.fold(
        (schedules) async {
          if (schedules.isEmpty) {
            LoggerService.warning('Nenhum agendamento habilitado encontrado');
            return;
          }

          LoggerService.info(
            'Encontrados ${schedules.length} agendamento(s) habilitado(s). Executando...',
          );

          int successCount = 0;
          int failureCount = 0;

          for (final schedule in schedules) {
            LoggerService.info('Executando backup: ${schedule.name}');

            final result = await schedulerService.executeNow(schedule.id);

            result.fold(
              (_) {
                successCount++;
                LoggerService.info(
                  'Backup concluído com sucesso: ${schedule.name}',
                );
              },
              (failure) {
                failureCount++;
                LoggerService.error(
                  'Erro ao executar backup: ${schedule.name}',
                  failure,
                );
              },
            );
          }

          LoggerService.info(
            'Backup manual concluído. Sucesso: $successCount, Falhas: $failureCount',
          );
        },
        (failure) async {
          LoggerService.error('Erro ao buscar agendamentos habilitados', failure);
        },
      );
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao executar backup manual', e, stackTrace);
    }
  }

  static void _navigateToSettings() {
    LoggerService.info('Navegando para configurações via tray menu');

    WindowManagerService().show();

    appRouter.go(RouteNames.settings);
  }

  static Future<void> _exitApp() async {
    await AppCleanup.cleanup();
    exit(0);
  }
}
