import 'package:backup_database/application/services/strategies/enrichers/sybase_chain_metadata_enricher.dart';
import 'package:backup_database/application/services/strategies/generic_database_backup_strategy.dart';
import 'package:backup_database/application/services/strategies/rules/sybase_log_backup_preflight_rule.dart';
import 'package:backup_database/application/services/strategies/rules/sybase_reject_differential_rule.dart';
import 'package:backup_database/application/services/strategies/rules/sybase_reject_truncate_in_replication_rule.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/use_cases/backup/validate_sybase_log_backup_preflight.dart';

class SybaseBackupStrategyFactory {
  static GenericDatabaseBackupStrategy<SybaseConfig> create({
    required ISybaseBackupService service,
    required ValidateSybaseLogBackupPreflight validatePreflight,
  }) {
    return GenericDatabaseBackupStrategy<SybaseConfig>(
      databaseType: DatabaseType.sybase,
      port: service,
      rules: [
        SybaseRejectDifferentialRule(),
        SybaseLogBackupPreflightRule(validatePreflight),
        SybaseRejectTruncateInReplicationRule(),
      ],
      enrichers: [SybaseChainMetadataEnricher()],
      buildContext:
          ({
            required Schedule schedule,
            required SybaseConfig config,
            required String outputDirectory,
            required BackupType backupType,
            required String cancelTag,
          }) {
            final SybaseBackupOptions? sybaseOptions =
                schedule.sybaseBackupOptions;
            return BackupExecutionContext(
              outputDirectory: outputDirectory,
              scheduleId: schedule.id,
              backupType: backupType,
              truncateLog: schedule.truncateLog,
              verifyAfterBackup: schedule.verifyAfterBackup,
              verifyPolicy: schedule.verifyPolicy,
              backupTimeout: schedule.backupTimeout,
              verifyTimeout: schedule.verifyTimeout,
              sybaseBackupOptions: sybaseOptions,
              cancelTag: cancelTag,
            );
          },
    );
  }
}
