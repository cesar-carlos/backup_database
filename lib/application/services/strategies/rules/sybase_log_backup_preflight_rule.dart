import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/backup_validation_rule.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/use_cases/backup/validate_sybase_log_backup_preflight.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SybaseLogBackupPreflightRule extends BackupValidationRule<SybaseConfig> {
  SybaseLogBackupPreflightRule(this._validatePreflight);

  final ValidateSybaseLogBackupPreflight _validatePreflight;

  @override
  Future<rd.Result<void>> validate(
    BackupPipelineContext context, {
    required Schedule schedule,
    required SybaseConfig config,
    required BackupType backupType,
  }) async {
    if (backupType != BackupType.log) {
      return const rd.Success(unit);
    }

    final preflightResult = await _validatePreflight(schedule);
    if (preflightResult.isError()) {
      return rd.Failure(preflightResult.exceptionOrNull()!);
    }
    final preflight = preflightResult.getOrNull();
    if (preflight == null) {
      return const rd.Failure(
        ValidationFailure(message: 'Preflight retornou resultado nulo'),
      );
    }
    if (!preflight.canProceed) {
      LoggerService.error('Preflight Sybase log: ${preflight.error}');
      return rd.Failure(
        ValidationFailure(
          message: preflight.error ?? 'Preflight falhou',
        ),
      );
    }
    if (preflight.warning != null) {
      LoggerService.warning('Preflight Sybase log: ${preflight.warning}');
    }
    context.sybaseLogPreflight = preflight;
    return const rd.Success(unit);
  }
}
