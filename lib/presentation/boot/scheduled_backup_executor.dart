import 'dart:io';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';

class ScheduledBackupExecutor {
  static Future<void> executeAndExit(String scheduleId) async {
    LoggerService.info('Executando backup agendado: $scheduleId');

    try {
      final schedulerService = service_locator.getIt<ISchedulerService>();
      await schedulerService.executeNow(scheduleId);
      LoggerService.info('Backup concluído');
    } on Object catch (e) {
      LoggerService.error('Erro no backup agendado: $e');
    }

    await AppCleanup.cleanup();
    exit(0);
  }
}
