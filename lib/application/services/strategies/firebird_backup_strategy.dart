import 'package:backup_database/application/services/strategies/firebird_backup_strategy_factory.dart';
import 'package:backup_database/application/services/strategies/i_database_backup_strategy.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';
import 'package:result_dart/result_dart.dart';

class FirebirdBackupStrategy implements IDatabaseBackupStrategy {
  FirebirdBackupStrategy(IFirebirdBackupService service)
    : _delegate = FirebirdBackupStrategyFactory.create(service);

  final IDatabaseBackupStrategy _delegate;

  @override
  DatabaseType get databaseType => _delegate.databaseType;

  @override
  Future<Result<BackupExecutionResult>> execute({
    required Schedule schedule,
    required Object databaseConfig,
    required String outputDirectory,
    required BackupType backupType,
    required String cancelTag,
  }) {
    return _delegate.execute(
      schedule: schedule,
      databaseConfig: databaseConfig,
      outputDirectory: outputDirectory,
      backupType: backupType,
      cancelTag: cancelTag,
    );
  }

  @override
  Future<Result<int>> getDatabaseSizeBytes({
    required Object databaseConfig,
    Duration? timeout,
  }) {
    return _delegate.getDatabaseSizeBytes(
      databaseConfig: databaseConfig,
      timeout: timeout,
    );
  }
}
