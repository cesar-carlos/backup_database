import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/backup_validation_rule.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SybaseRejectDifferentialRule extends BackupValidationRule<SybaseConfig> {
  @override
  Future<rd.Result<void>> validate(
    BackupPipelineContext context, {
    required Schedule schedule,
    required SybaseConfig config,
    required BackupType backupType,
  }) async {
    if (backupType != BackupType.differential) {
      return const rd.Success(unit);
    }
    const message =
        'Sybase SQL Anywhere não suporta backup differential nativo. '
        'Configure o agendamento como Full ou Log de Transações.';
    LoggerService.error(message);
    return const rd.Failure(ValidationFailure(message: message));
  }
}
