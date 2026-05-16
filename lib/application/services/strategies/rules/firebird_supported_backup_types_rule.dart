import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/backup_validation_rule.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:result_dart/result_dart.dart' as rd;

class FirebirdSupportedBackupTypesRule
    extends BackupValidationRule<FirebirdConfig> {
  @override
  Future<rd.Result<void>> validate(
    BackupPipelineContext context, {
    required Schedule schedule,
    required FirebirdConfig config,
    required BackupType backupType,
  }) async {
    switch (backupType) {
      case BackupType.full:
      case BackupType.fullSingle:
        return const rd.Success(unit);
      case BackupType.log:
      case BackupType.differential:
      case BackupType.convertedDifferential:
      case BackupType.convertedFullSingle:
      case BackupType.convertedLog:
        return const rd.Failure(
          ValidationFailure(
            message:
                'Firebird suporta apenas backup completo (Full ou Full Single). '
                'Tipos de log, diferencial ou convertidos nao estao disponiveis.',
          ),
        );
    }
  }
}
