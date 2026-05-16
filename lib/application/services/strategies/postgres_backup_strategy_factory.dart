import 'package:backup_database/application/services/strategies/backup_result_enricher.dart';
import 'package:backup_database/application/services/strategies/generic_database_backup_strategy.dart';
import 'package:backup_database/application/services/strategies/rules/postgres_reject_converted_types_rule.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';

class PostgresBackupStrategyFactory {
  static GenericDatabaseBackupStrategy<PostgresConfig> create(
    IPostgresBackupService service,
  ) {
    return GenericDatabaseBackupStrategy<PostgresConfig>(
      databaseType: DatabaseType.postgresql,
      port: service,
      rules: [PostgresRejectConvertedTypesRule()],
      enrichers: <BackupResultEnricher<PostgresConfig>>[],
      buildContext:
          ({
            required Schedule schedule,
            required PostgresConfig config,
            required String outputDirectory,
            required BackupType backupType,
            required String cancelTag,
          }) {
            return BackupExecutionContext(
              outputDirectory: outputDirectory,
              scheduleId: schedule.id,
              backupType: backupType,
              verifyAfterBackup: schedule.verifyAfterBackup,
              backupTimeout: schedule.backupTimeout,
              verifyTimeout: schedule.verifyTimeout,
              cancelTag: cancelTag,
            );
          },
    );
  }
}
