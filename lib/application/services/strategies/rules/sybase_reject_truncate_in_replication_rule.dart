import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/backup_validation_rule.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SybaseRejectTruncateInReplicationRule
    extends BackupValidationRule<SybaseConfig> {
  @override
  Future<rd.Result<void>> validate(
    BackupPipelineContext context, {
    required Schedule schedule,
    required SybaseConfig config,
    required BackupType backupType,
  }) async {
    final SybaseBackupOptions? sybaseOptions = schedule.sybaseBackupOptions;
    if (sybaseOptions == null) {
      LoggerService.warning(
        'Schedule "${schedule.name}" do tipo Sybase foi carregado sem '
        'SybaseBackupOptions. Backup usará defaults seguros.',
      );
    }

    if (config.isReplicationEnvironment &&
        backupType == BackupType.log &&
        (sybaseOptions ?? SybaseBackupOptions.safeDefaults).effectiveLogMode(
              truncateLog: schedule.truncateLog,
            ) ==
            SybaseLogBackupMode.truncate) {
      const message =
          'Backup de log com modo Truncar (TRUNCATE) não é permitido em '
          'ambientes de replicação (SQL Remote, MobiLink). '
          'Use modo Renomear ou Apenas na configuração do agendamento.';
      LoggerService.error(message);
      return const rd.Failure(ValidationFailure(message: message));
    }
    return const rd.Success(unit);
  }
}
