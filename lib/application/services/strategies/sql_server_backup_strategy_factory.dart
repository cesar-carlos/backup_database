import 'package:backup_database/application/services/strategies/backup_result_enricher.dart';
import 'package:backup_database/application/services/strategies/generic_database_backup_strategy.dart';
import 'package:backup_database/application/services/strategies/rules/sql_server_reject_converted_types_rule.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';

class SqlServerBackupStrategyFactory {
  static GenericDatabaseBackupStrategy<SqlServerConfig> create(
    ISqlServerBackupService service,
  ) {
    return GenericDatabaseBackupStrategy<SqlServerConfig>(
      databaseType: DatabaseType.sqlServer,
      port: service,
      rules: [SqlServerRejectConvertedTypesRule()],
      enrichers: <BackupResultEnricher<SqlServerConfig>>[],
      buildContext:
          ({
            required Schedule schedule,
            required SqlServerConfig config,
            required String outputDirectory,
            required BackupType backupType,
            required String cancelTag,
          }) {
            final backupOptions = schedule.sqlServerBackupOptions;
            if (backupOptions == null) {
              LoggerService.warning(
                'Schedule "${schedule.name}" do tipo SQL Server foi carregado '
                'sem SqlServerBackupOptions. Backup usará defaults do servidor.',
              );
            }
            return BackupExecutionContext(
              outputDirectory: outputDirectory,
              scheduleId: schedule.id,
              backupType: backupType,
              truncateLog: schedule.truncateLog,
              enableChecksum: schedule.enableChecksum,
              verifyAfterBackup: schedule.verifyAfterBackup,
              verifyPolicy: schedule.verifyPolicy,
              backupTimeout: schedule.backupTimeout,
              verifyTimeout: schedule.verifyTimeout,
              sqlServerBackupOptions: backupOptions,
              cancelTag: cancelTag,
            );
          },
    );
  }
}
