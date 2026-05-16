import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class BackupValidationRule<T extends DatabaseConnectionConfig> {
  Future<rd.Result<void>> validate(
    BackupPipelineContext context, {
    required Schedule schedule,
    required T config,
    required BackupType backupType,
  });
}
