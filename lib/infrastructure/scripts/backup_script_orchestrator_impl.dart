import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/services/i_backup_script_orchestrator.dart';
import 'package:backup_database/domain/services/i_sql_script_execution_service.dart';
import 'package:result_dart/result_dart.dart';

/// Implementation of [IBackupScriptOrchestrator].
class BackupScriptOrchestratorImpl implements IBackupScriptOrchestrator {
  const BackupScriptOrchestratorImpl();

  @override
  Future<Result<void>> executePostBackupScript({
    required String historyId,
    required Schedule schedule,
    required ISqlServerConfigRepository sqlServerConfigRepository,
    required ISybaseConfigRepository sybaseConfigRepository,
    required IPostgresConfigRepository postgresConfigRepository,
    required ISqlScriptExecutionService scriptService,
    required IBackupLogRepository logRepository,
  }) async {
    if (schedule.postBackupScript == null ||
        schedule.postBackupScript!.trim().isEmpty) {
      return const Success(unit);
    }

    await _log(
      logRepository,
      historyId,
      'info',
      'Executando script SQL pós-backup',
    );

    try {
      SqlServerConfig? sqlServerConfig;
      SybaseConfig? sybaseConfig;
      PostgresConfig? postgresConfig;

      // Get appropriate config based on database type
      if (schedule.databaseType == DatabaseType.sqlServer) {
        final configResult = await sqlServerConfigRepository.getById(
          schedule.databaseConfigId,
        );
        if (configResult.isSuccess()) {
          sqlServerConfig = configResult.getOrNull();
        }
      } else if (schedule.databaseType == DatabaseType.sybase) {
        final configResult = await sybaseConfigRepository.getById(
          schedule.databaseConfigId,
        );
        if (configResult.isSuccess()) {
          sybaseConfig = configResult.getOrNull();
        }
      } else if (schedule.databaseType == DatabaseType.postgresql) {
        final configResult = await postgresConfigRepository.getById(
          schedule.databaseConfigId,
        );
        if (configResult.isSuccess()) {
          postgresConfig = configResult.getOrNull();
        }
      }

      final scriptResult = await scriptService.executeScript(
        databaseType: schedule.databaseType,
        sqlServerConfig: sqlServerConfig,
        sybaseConfig: sybaseConfig,
        postgresConfig: postgresConfig,
        script: schedule.postBackupScript!,
      );

      return scriptResult.fold(
        (_) async {
          await _log(
            logRepository,
            historyId,
            'info',
            'Script SQL executado com sucesso',
          );
          return const Success(unit);
        },
        (failure) async {
          final errorMessage = failure.toString();
          LoggerService.warning(
            'Erro ao executar script SQL pós-backup: $errorMessage',
            failure,
          );
          await _log(
            logRepository,
            historyId,
            'warning',
            'Script SQL pós-backup falhou: $errorMessage',
          );
          // Script failure is not critical, return success
          return const Success(unit);
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro inesperado ao executar script SQL',
        e,
        stackTrace,
      );
      await _log(
        logRepository,
        historyId,
        'warning',
        'Erro ao executar script SQL pós-backup: $e',
      );
      // Script failure is not critical, return success
      return const Success(unit);
    }
  }

  Future<void> _log(
    IBackupLogRepository repository,
    String historyId,
    String levelStr,
    String message,
  ) async {
    LogLevel level;
    switch (levelStr) {
      case 'info':
        level = LogLevel.info;
      case 'warning':
        level = LogLevel.warning;
      case 'error':
        level = LogLevel.error;
      default:
        level = LogLevel.info;
    }

    final log = BackupLog(
      backupHistoryId: historyId,
      level: level,
      category: LogCategory.execution,
      message: message,
    );
    await repository.create(log);
  }
}
