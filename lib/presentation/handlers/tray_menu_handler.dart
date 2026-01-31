import 'dart:io';

import 'package:backup_database/application/services/scheduler_service.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';
import 'package:backup_database/presentation/managers/managers.dart';

class TrayMenuHandler {
  static void handleAction(TrayMenuAction action) {
    switch (action) {
      case TrayMenuAction.show:
        WindowManagerService().show();

      case TrayMenuAction.executeBackup:
        _executeManualBackup();

      case TrayMenuAction.pauseScheduler:
        service_locator.getIt<SchedulerService>().stop();
        TrayManagerService().setSchedulerPaused(true);

      case TrayMenuAction.resumeScheduler:
        service_locator.getIt<SchedulerService>().start();
        TrayManagerService().setSchedulerPaused(false);

      case TrayMenuAction.settings:
        _navigateToSettings();

      case TrayMenuAction.exit:
        _exitApp();
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

          var successCount = 0;
          var failureCount = 0;

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
          LoggerService.error(
            'Erro ao buscar agendamentos habilitados',
            failure,
          );
        },
      );
    } on Object catch (e, stackTrace) {
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
