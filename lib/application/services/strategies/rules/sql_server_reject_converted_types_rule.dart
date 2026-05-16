import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/backup_validation_rule.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SqlServerRejectConvertedTypesRule
    extends BackupValidationRule<SqlServerConfig> {
  @override
  Future<rd.Result<void>> validate(
    BackupPipelineContext context, {
    required Schedule schedule,
    required SqlServerConfig config,
    required BackupType backupType,
  }) async {
    switch (backupType) {
      case BackupType.convertedDifferential:
      case BackupType.convertedFullSingle:
      case BackupType.convertedLog:
        return const rd.Failure(
          ValidationFailure(
            message:
                'SQL Server não suporta tipos convertidos de backup do Sybase. '
                'Use um tipo de backup nativo do SQL Server.',
          ),
        );
      case BackupType.full:
      case BackupType.fullSingle:
      case BackupType.differential:
      case BackupType.log:
        return const rd.Success(unit);
    }
  }
}
