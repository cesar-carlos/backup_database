import 'dart:io';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/utils/uuid_validator.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';

/// Códigos de saída para execução agendada (consumidos pelo Task Scheduler
/// do Windows e por monitores externos como Nagios/Zabbix). Quanto mais
/// granular, melhor a triagem de incidentes — antes, todo erro virava
/// `exit(0)` indistinguível do sucesso.
abstract class ScheduledBackupExitCode {
  static const int success = 0;
  static const int genericFailure = 1;
  static const int invalidScheduleId = 2;
}

class ScheduledBackupExecutor {
  static Future<void> executeAndExit(String scheduleId) async {
    LoggerService.info('Executando backup agendado: $scheduleId');

    if (!UuidValidator.isValid(scheduleId)) {
      LoggerService.error(
        'scheduleId inválido recebido em --schedule-id="$scheduleId"; '
        'esperado um UUID v1-v5.',
      );
      await AppCleanup.cleanup();
      exit(ScheduledBackupExitCode.invalidScheduleId);
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
      LoggerService.error('Erro no backup agendado: $e', e, s);
      exitCode = ScheduledBackupExitCode.genericFailure;
    }

    await AppCleanup.cleanup();
    exit(exitCode);
  }
}
