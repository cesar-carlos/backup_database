import 'package:backup_database/application/services/strategies/generic_database_backup_strategy.dart';
import 'package:backup_database/application/services/strategies/rules/firebird_supported_backup_types_rule.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';

class FirebirdBackupStrategyFactory {
  static GenericDatabaseBackupStrategy<FirebirdConfig> create(
    IFirebirdBackupService service,
  ) {
    return GenericDatabaseBackupStrategy<FirebirdConfig>(
      databaseType: DatabaseType.firebird,
      port: service,
      rules: [FirebirdSupportedBackupTypesRule()],
      enrichers: [],
      buildContext:
          ({
            required Schedule schedule,
            required FirebirdConfig config,
            required String outputDirectory,
            required BackupType backupType,
            required String cancelTag,
          }) {
            return BackupExecutionContext(
              outputDirectory: outputDirectory,
              scheduleId: schedule.id,
              backupType: backupType,
              verifyAfterBackup: schedule.verifyAfterBackup,
              verifyPolicy: schedule.verifyPolicy,
              enableChecksum: schedule.enableChecksum,
              backupTimeout: schedule.backupTimeout,
              verifyTimeout: schedule.verifyTimeout,
              cancelTag: cancelTag,
              firebirdNbackupPhysicalLevel:
                  schedule.firebirdNbackupPhysicalLevel,
            );
          },
    );
  }
}
