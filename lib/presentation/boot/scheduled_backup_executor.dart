import 'dart:io';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/exit_codes.dart';
import 'package:backup_database/core/utils/schedule_args.dart';
import 'package:backup_database/core/utils/uuid_validator.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';

export 'package:backup_database/core/exit_codes.dart'
    show ScheduledBackupExitCode;

class ScheduledBackupExecutor {
  static Future<void> executeAndExit(String scheduleId) async {
    final exitCode = await execute(scheduleId);
    await AppCleanup.cleanup();
    exit(exitCode);
  }

  static Future<int> execute(String scheduleId) async {
    LoggerService.info('Executando backup agendado: $scheduleId');

    if (!UuidValidator.isValid(scheduleId)) {
      LoggerService.error(
        'scheduleId inválido recebido em '
        '$scheduleIdArgumentPrefix"$scheduleId"; esperado um UUID v1-v5.',
      );
      return ScheduledBackupExitCode.invalidScheduleId;
    }

    var exitCode = ScheduledBackupExitCode.success;
    try {
      final schedulerService = service_locator.getIt<ISchedulerService>();
      await schedulerService.executeNow(scheduleId);
      LoggerService.info('Backup concluído');
    } on Object catch (e, s) {
      // Propaga falha como exit code != 0 para que o Task Scheduler /
      // monitores externos detectem (antes era sempre exit 0, mascarando
      // falhas). Mantém o cleanup mesmo no caminho de erro.
      LoggerService.error('Erro no backup agendado', e, s);
      exitCode = ScheduledBackupExitCode.genericFailure;
    }

    return exitCode;
  }
}
