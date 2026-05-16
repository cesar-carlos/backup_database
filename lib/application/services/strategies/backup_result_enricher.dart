import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';

abstract class BackupResultEnricher<T extends DatabaseConnectionConfig> {
  Future<BackupExecutionResult> enrich(
    BackupPipelineContext context, {
    required Schedule schedule,
    required T config,
    required BackupType backupType,
    required BackupExecutionResult result,
  });
}
