import 'dart:io';

import '../../core/core.dart';
import '../../core/di/service_locator.dart' as service_locator;
import 'app_cleanup.dart';
import '../../application/services/scheduler_service.dart';

class ScheduledBackupExecutor {
  static Future<void> executeAndExit(String scheduleId) async {
    LoggerService.info('Executando backup agendado: $scheduleId');

    try {
      final schedulerService = service_locator.getIt<SchedulerService>();
      await schedulerService.executeNow(scheduleId);
      LoggerService.info('Backup concluído');
    } catch (e) {
      LoggerService.error('Erro no backup agendado: $e');
    }

    await AppCleanup.cleanup();
    exit(0);
  }
}
