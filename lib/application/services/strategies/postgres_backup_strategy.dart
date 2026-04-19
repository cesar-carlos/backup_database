import 'package:backup_database/application/services/strategies/i_database_backup_strategy.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:result_dart/result_dart.dart';

/// Estratégia de backup específica para PostgreSQL.
class PostgresBackupStrategy implements IDatabaseBackupStrategy {
  PostgresBackupStrategy(this._service);

  final IPostgresBackupService _service;

  @override
  DatabaseType get databaseType => DatabaseType.postgresql;

  @override
  Future<Result<BackupExecutionResult>> execute({
    required Schedule schedule,
    required Object databaseConfig,
    required String outputDirectory,
    required BackupType backupType,
    required String cancelTag,
  }) {
    final config = databaseConfig as PostgresConfig;
    return _service.executeBackup(
      config: config,
      outputDirectory: outputDirectory,
      backupType: backupType,
      verifyAfterBackup: schedule.verifyAfterBackup,
      backupTimeout: schedule.backupTimeout,
      verifyTimeout: schedule.verifyTimeout,
      cancelTag: cancelTag,
    );
  }
}
