import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/i_backup_compression_orchestrator.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_backup_script_orchestrator.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/domain/services/i_sql_script_execution_service.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/use_cases/backup/get_database_config.dart';
import 'package:backup_database/domain/use_cases/storage/validate_backup_directory.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class BackupOrchestratorService {
  BackupOrchestratorService({
    required ISqlServerConfigRepository sqlServerConfigRepository,
    required ISybaseConfigRepository sybaseConfigRepository,
    required IPostgresConfigRepository postgresConfigRepository,
    required IBackupHistoryRepository backupHistoryRepository,
    required IBackupLogRepository backupLogRepository,
    required ISqlServerBackupService sqlServerBackupService,
    required ISybaseBackupService sybaseBackupService,
    required IPostgresBackupService postgresBackupService,
    required IBackupCompressionOrchestrator compressionOrchestrator,
    required IBackupScriptOrchestrator scriptOrchestrator,
    required ISqlScriptExecutionService sqlScriptExecutionService,
    required INotificationService notificationService,
    required IBackupProgressNotifier progressNotifier,
    required GetDatabaseConfig getDatabaseConfig,
    required ValidateBackupDirectory validateBackupDirectory,
  }) : _sqlServerConfigRepository = sqlServerConfigRepository,
       _sybaseConfigRepository = sybaseConfigRepository,
       _postgresConfigRepository = postgresConfigRepository,
       _backupHistoryRepository = backupHistoryRepository,
       _backupLogRepository = backupLogRepository,
       _sqlServerBackupService = sqlServerBackupService,
       _sybaseBackupService = sybaseBackupService,
       _postgresBackupService = postgresBackupService,
       _compressionOrchestrator = compressionOrchestrator,
       _scriptOrchestrator = scriptOrchestrator,
       _sqlScriptExecutionService = sqlScriptExecutionService,
       _notificationService = notificationService,
       _progressNotifier = progressNotifier,
       _getDatabaseConfig = getDatabaseConfig,
       _validateBackupDirectory = validateBackupDirectory;
  final ISqlServerConfigRepository _sqlServerConfigRepository;
  final ISybaseConfigRepository _sybaseConfigRepository;
  final IPostgresConfigRepository _postgresConfigRepository;
  final IBackupHistoryRepository _backupHistoryRepository;
  final IBackupLogRepository _backupLogRepository;
  final ISqlServerBackupService _sqlServerBackupService;
  final ISybaseBackupService _sybaseBackupService;
  final IPostgresBackupService _postgresBackupService;
  final IBackupCompressionOrchestrator _compressionOrchestrator;
  final IBackupScriptOrchestrator _scriptOrchestrator;
  final ISqlScriptExecutionService _sqlScriptExecutionService;
  final INotificationService _notificationService;
  final IBackupProgressNotifier _progressNotifier;
  final GetDatabaseConfig _getDatabaseConfig;
  final ValidateBackupDirectory _validateBackupDirectory;

  Future<rd.Result<BackupHistory>> executeBackup({
    required Schedule schedule,
    required String outputDirectory,
  }) async {
    LoggerService.info('Iniciando backup para schedule: ${schedule.name}');

    if (outputDirectory.isEmpty) {
      final errorMessage =
          'Caminho de saída do backup está vazio para o agendamento: '
          '${schedule.name}';
      LoggerService.error(errorMessage);
      return rd.Failure(ValidationFailure(message: errorMessage));
    }

    final backupType =
        (schedule.databaseType != DatabaseType.postgresql &&
            schedule.backupType == BackupType.fullSingle)
        ? BackupType.full
        : schedule.backupType;

    final typeFolderName = backupType.displayName;
    final typeOutputDirectory = p.join(outputDirectory, typeFolderName);

    // Validate output directory
    final validationResult = await _validateBackupDirectory(typeOutputDirectory);
    if (validationResult.isError()) {
      final failure = validationResult.exceptionOrNull()!;
      LoggerService.error('Directory validation failed', failure);
      return rd.Failure(failure);
    }

    LoggerService.info(
      'Diretório de backup por tipo: $typeOutputDirectory '
      '(Tipo: ${backupType.displayName})',
    );

    var history = BackupHistory(
      scheduleId: schedule.id,
      databaseName: schedule.name,
      databaseType: schedule.databaseType.name,
      backupPath: '',
      fileSize: 0,
      backupType: backupType.name,
      status: BackupStatus.running,
      startedAt: DateTime.now(),
    );

    final createResult = await _backupHistoryRepository.create(history);
    if (createResult.isError()) {
      return rd.Failure(createResult.exceptionOrNull()!);
    }
    history = createResult.getOrNull()!;

    await _log(history.id, 'info', 'Backup iniciado');

    try {
      String backupPath;
      int fileSize;

      // Get database configuration using centralized use case
      final configResult = await _getDatabaseConfig(
        schedule.databaseConfigId,
        schedule.databaseType,
      );

      if (configResult.isError()) {
        final failure = configResult.exceptionOrNull();
        final errorMessage = 'DatabaseType: ${schedule.databaseType}, '
            'ConfigId: ${schedule.databaseConfigId}';
        LoggerService.error(
          'Failed to get database configuration: $errorMessage',
          failure,
        );
        return rd.Failure(
          ConfigNotFoundFailure(
            message: 'Configuration not found for ${schedule.databaseType.name} '
                '(id: ${schedule.databaseConfigId})',
            originalError: failure,
          ),
        );
      }

      // Execute backup based on database type
      if (schedule.databaseType == DatabaseType.sqlServer) {
        final config = configResult.getOrNull()! as SqlServerConfig;
        final backupResult = await _sqlServerBackupService.executeBackup(
          config: config,
          outputDirectory: typeOutputDirectory,
          backupType: backupType,
          truncateLog: schedule.truncateLog,
          enableChecksum: schedule.enableChecksum,
          verifyAfterBackup: schedule.verifyAfterBackup,
        );

        if (backupResult.isError()) {
          final failure = backupResult.exceptionOrNull()! as Failure;
          return rd.Failure(failure);
        }

        backupPath = backupResult.getOrNull()!.backupPath;
        fileSize = backupResult.getOrNull()!.fileSize;
      } else if (schedule.databaseType == DatabaseType.sybase) {
        final config = configResult.getOrNull()! as SybaseConfig;
        final backupResult = await _sybaseBackupService.executeBackup(
          config: config,
          outputDirectory: typeOutputDirectory,
          backupType: backupType,
          truncateLog: schedule.truncateLog,
          verifyAfterBackup: schedule.verifyAfterBackup,
        );

        if (backupResult.isError()) {
          final failure = backupResult.exceptionOrNull()! as Failure;
          return rd.Failure(failure);
        }

        backupPath = backupResult.getOrNull()!.backupPath;
        fileSize = backupResult.getOrNull()!.fileSize;
      } else if (schedule.databaseType == DatabaseType.postgresql) {
        final config = configResult.getOrNull()! as PostgresConfig;
        final backupResult = await _postgresBackupService.executeBackup(
          config: config,
          outputDirectory: typeOutputDirectory,
          backupType: backupType,
          verifyAfterBackup: schedule.verifyAfterBackup,
        );

        if (backupResult.isError()) {
          final failure = backupResult.exceptionOrNull()! as Failure;
          return rd.Failure(failure);
        }

        backupPath = backupResult.getOrNull()!.backupPath;
        fileSize = backupResult.getOrNull()!.fileSize;
      } else {
        return rd.Failure(
          ValidationFailure(
            message: 'Unsupported database type: ${schedule.databaseType}',
          ),
        );
      }

      await _log(history.id, 'info', 'Backup do banco concluído');

      try {
        _progressNotifier.updateProgress(
          step: 'Executando backup',
          message: 'Backup do banco concluído',
          progress: 0.5,
        );
      } on Object catch (e, s) {
        LoggerService.warning('Erro ao atualizar progresso', e, s);
      }

      if (schedule.compressionFormat != CompressionFormat.none) {
        await _log(history.id, 'info', 'Iniciando compressão');

        final compressionResult = await _compressionOrchestrator.compressBackup(
          backupPath: backupPath,
          format: schedule.compressionFormat,
          databaseType: schedule.databaseType,
          backupType: backupType,
          progressNotifier: _progressNotifier,
        );

        if (compressionResult.isSuccess()) {
          final result = compressionResult.getOrNull()!;
          backupPath = result.compressedPath;
          fileSize = result.compressedSize;
          await _log(history.id, 'info', 'Compressão concluída');
        } else {
          final failure = compressionResult.exceptionOrNull()!;
          final failureMessage = failure.toString();

          LoggerService.error('Falha na compressão: $failureMessage', failure);
          await _log(
            history.id,
            'error',
            'Falha na compressão: $failureMessage',
          );

          return rd.Failure(failure);
        }
      }

      if (schedule.postBackupScript != null &&
          schedule.postBackupScript!.trim().isNotEmpty) {
        await _log(history.id, 'info', 'Executando script SQL pós-backup');

        await _scriptOrchestrator.executePostBackupScript(
          historyId: history.id,
          schedule: schedule,
          sqlServerConfigRepository: _sqlServerConfigRepository,
          sybaseConfigRepository: _sybaseConfigRepository,
          postgresConfigRepository: _postgresConfigRepository,
          scriptService: _sqlScriptExecutionService,
          logRepository: _backupLogRepository,
        );
      }

      final finishedAt = DateTime.now();
      history = history.copyWith(
        backupPath: backupPath,
        fileSize: fileSize,
        status: BackupStatus.success,
        finishedAt: finishedAt,
        durationSeconds: finishedAt.difference(history.startedAt).inSeconds,
      );

      await _backupHistoryRepository.update(history);
      await _log(history.id, 'info', 'Backup finalizado com sucesso');

      LoggerService.info('Backup concluído: ${history.backupPath}');
      return rd.Success(history);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro no backup', e, stackTrace);

      final finishedAt = DateTime.now();
      history = history.copyWith(
        status: BackupStatus.error,
        errorMessage: e.toString(),
        finishedAt: finishedAt,
        durationSeconds: finishedAt.difference(history.startedAt).inSeconds,
      );

      await _backupHistoryRepository.update(history);
      await _log(history.id, 'error', 'Erro no backup: $e');

      await _notificationService.notifyBackupComplete(history);

      return rd.Failure(
        BackupFailure(message: 'Erro ao executar backup: $e', originalError: e),
      );
    }
  }

  Future<void> _log(String historyId, String levelStr, String message) async {
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
    await _backupLogRepository.create(log);
  }
}
