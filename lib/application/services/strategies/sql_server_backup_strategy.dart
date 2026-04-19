import 'package:backup_database/application/services/strategies/i_database_backup_strategy.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sql_server_backup_schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:result_dart/result_dart.dart';

/// Estratégia de backup específica para SQL Server.
class SqlServerBackupStrategy implements IDatabaseBackupStrategy {
  SqlServerBackupStrategy(this._service);

  final ISqlServerBackupService _service;

  @override
  DatabaseType get databaseType => DatabaseType.sqlServer;

  @override
  Future<Result<BackupExecutionResult>> execute({
    required Schedule schedule,
    required Object databaseConfig,
    required String outputDirectory,
    required BackupType backupType,
    required String cancelTag,
  }) {
    final config = databaseConfig as SqlServerConfig;
    // Quando o schedule é o tipo base (Schedule), opções avançadas
    // específicas do SQL Server não foram persistidas. Avisa em log
    // para ajudar diagnóstico (sem checksum/compression nativa).
    final SqlServerBackupOptions? backupOptions;
    if (schedule is SqlServerBackupSchedule) {
      backupOptions = schedule.sqlServerBackupOptions;
    } else {
      backupOptions = null;
      LoggerService.warning(
        'Schedule "${schedule.name}" do tipo SQL Server foi carregado '
        'sem SqlServerBackupOptions. Backup usará defaults do servidor.',
      );
    }

    return _service.executeBackup(
      config: config,
      outputDirectory: outputDirectory,
      scheduleId: schedule.id,
      backupType: backupType,
      truncateLog: schedule.truncateLog,
      enableChecksum: schedule.enableChecksum,
      verifyAfterBackup: schedule.verifyAfterBackup,
      verifyPolicy: schedule.verifyPolicy,
      sqlServerBackupOptions: backupOptions,
      cancelTag: cancelTag,
    );
  }
}
