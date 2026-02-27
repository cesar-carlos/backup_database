import 'package:backup_database/core/constants/backup_constants.dart';
import 'package:backup_database/core/constants/log_step_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_backup_schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_backup_schedule.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_backup_compression_orchestrator.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_backup_script_orchestrator.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/domain/services/i_sql_script_execution_service.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/services/i_storage_checker.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/use_cases/backup/get_database_config.dart';
import 'package:backup_database/domain/use_cases/backup/validate_sybase_log_backup_preflight.dart';
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
    required ValidateSybaseLogBackupPreflight validateSybaseLogBackupPreflight,
    required IStorageChecker storageChecker,
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
       _validateBackupDirectory = validateBackupDirectory,
       _validateSybaseLogBackupPreflight = validateSybaseLogBackupPreflight,
       _storageChecker = storageChecker;
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
  final ValidateSybaseLogBackupPreflight _validateSybaseLogBackupPreflight;
  final IStorageChecker _storageChecker;

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

    final typeFolderName = getBackupTypeDisplayName(backupType);
    final typeOutputDirectory = p.join(outputDirectory, typeFolderName);

    // Validate output directory
    final validationResult = await _validateBackupDirectory(
      typeOutputDirectory,
    );
    if (validationResult.isError()) {
      final failure = validationResult.exceptionOrNull()!;
      LoggerService.error('Directory validation failed', failure);
      return rd.Failure(failure);
    }

    // Validate minimum free disk space
    final spaceResult = await _storageChecker.checkSpace(typeOutputDirectory);
    if (spaceResult.isError()) {
      final failure = spaceResult.exceptionOrNull()!;
      LoggerService.error('Free space check failed', failure);
      return rd.Failure(failure);
    }
    final spaceInfo = spaceResult.getOrNull()!;
    if (!spaceInfo.hasEnoughSpace(BackupConstants.minFreeSpaceForBackupBytes)) {
      final errorMessage =
          'Espaço livre insuficiente no destino do backup. '
          'Disponível: ${_formatBytes(spaceInfo.freeBytes)}, '
          'Mínimo necessário: ${_formatBytes(BackupConstants.minFreeSpaceForBackupBytes)}';
      LoggerService.error(errorMessage);
      return rd.Failure(ValidationFailure(message: errorMessage));
    }

    LoggerService.info(
      'Diretório de backup por tipo: $typeOutputDirectory '
      '(Tipo: ${getBackupTypeDisplayName(backupType)})',
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

    await _log(
      history.id,
      'info',
      'Backup iniciado',
      step: LogStepConstants.backupStarted,
    );

    try {
      String backupPath;
      int fileSize;
      SybaseLogBackupPreflightResult? sybaseLogPreflight;

      // Get database configuration using centralized use case
      final configResult = await _getDatabaseConfig(
        schedule.databaseConfigId,
        schedule.databaseType,
      );

      if (configResult.isError()) {
        final failure = configResult.exceptionOrNull();
        final errorMessage =
            'DatabaseType: ${schedule.databaseType}, '
            'ConfigId: ${schedule.databaseConfigId}';
        LoggerService.error(
          'Failed to get database configuration: $errorMessage',
          failure,
        );
        return rd.Failure(
          ConfigNotFoundFailure(
            message:
                'Configuration not found for ${schedule.databaseType.name} '
                '(id: ${schedule.databaseConfigId})',
            code: FailureCodes.configNotFound,
            originalError: failure,
          ),
        );
      }

      BackupExecutionResult backupExecutionResult;
      if (schedule.databaseType == DatabaseType.sqlServer) {
        final config = configResult.getOrNull()! as SqlServerConfig;
        final backupOptions = schedule is SqlServerBackupSchedule
            ? schedule.sqlServerBackupOptions
            : null;
        final backupResult = await _sqlServerBackupService.executeBackup(
          config: config,
          outputDirectory: typeOutputDirectory,
          scheduleId: schedule.id,
          backupType: backupType,
          truncateLog: schedule.truncateLog,
          enableChecksum: schedule.enableChecksum,
          verifyAfterBackup: schedule.verifyAfterBackup,
          verifyPolicy: schedule.verifyPolicy,
          sqlServerBackupOptions: backupOptions,
        );

        if (backupResult.isError()) {
          final failure = backupResult.exceptionOrNull()! as Failure;
          return rd.Failure(failure);
        }

        backupExecutionResult = backupResult.getOrNull()!;
      } else if (schedule.databaseType == DatabaseType.sybase) {
        if (backupType == BackupType.log) {
          final preflightResult =
              await _validateSybaseLogBackupPreflight(schedule);
          if (preflightResult.isError()) {
            return rd.Failure(preflightResult.exceptionOrNull()!);
          }
          final preflight = preflightResult.getOrNull()!;
          if (!preflight.canProceed) {
            LoggerService.error('Preflight Sybase log: ${preflight.error}');
            return rd.Failure(
              ValidationFailure(message: preflight.error ?? 'Preflight falhou'),
            );
          }
          if (preflight.warning != null) {
            LoggerService.warning('Preflight Sybase log: ${preflight.warning}');
          }
          sybaseLogPreflight = preflight;
        }

        final config = configResult.getOrNull()! as SybaseConfig;
        final sybaseOptions = schedule is SybaseBackupSchedule
            ? schedule.sybaseBackupOptions
            : null;
        if (config.isReplicationEnvironment &&
            backupType == BackupType.log &&
            _effectiveSybaseLogMode(sybaseOptions, schedule.truncateLog) ==
                SybaseLogBackupMode.truncate) {
          const message =
              'Backup de log com modo Truncar (TRUNCATE) não é permitido em '
              'ambientes de replicação (SQL Remote, MobiLink). '
              'Use modo Renomear ou Apenas na configuração do agendamento.';
          LoggerService.error(message);
          return const rd.Failure(ValidationFailure(message: message));
        }
        final backupResult = await _sybaseBackupService.executeBackup(
          config: config,
          outputDirectory: typeOutputDirectory,
          backupType: backupType,
          truncateLog: schedule.truncateLog,
          verifyAfterBackup: schedule.verifyAfterBackup,
          verifyPolicy: schedule.verifyPolicy,
          backupTimeout: schedule.backupTimeout,
          verifyTimeout: schedule.verifyTimeout,
          sybaseBackupOptions: sybaseOptions,
        );

        if (backupResult.isError()) {
          final failure = backupResult.exceptionOrNull()! as Failure;
          return rd.Failure(failure);
        }

        backupExecutionResult = backupResult.getOrNull()!;
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

        backupExecutionResult = backupResult.getOrNull()!;
      } else {
        return rd.Failure(
          ValidationFailure(
            message: 'Unsupported database type: ${schedule.databaseType}',
          ),
        );
      }

      backupPath = backupExecutionResult.backupPath;
      fileSize = backupExecutionResult.fileSize;

      await _log(
        history.id,
        'info',
        'Backup do banco concluído',
        step: LogStepConstants.backupDbDone,
      );

      try {
        _progressNotifier.updateProgress(
          step: 'Executando backup',
          message: 'Backup do banco concluído',
          progress: 0.5,
        );
      } on Object catch (e, s) {
        LoggerService.warning('Erro ao atualizar progresso', e, s);
      }

      var compressionDuration = Duration.zero;
      if (schedule.compressionFormat != CompressionFormat.none) {
        await _log(
          history.id,
          'info',
          'Iniciando compressão',
          step: LogStepConstants.compressionStarted,
        );

        final compressionResult = await _compressionOrchestrator.compressBackup(
          backupPath: backupPath,
          format: schedule.compressionFormat ?? CompressionFormat.none,
          databaseType: schedule.databaseType,
          backupType: backupType,
          progressNotifier: _progressNotifier,
        );

        if (compressionResult.isSuccess()) {
          final result = compressionResult.getOrNull()!;
          backupPath = result.compressedPath;
          fileSize = result.compressedSize;
          compressionDuration = result.duration;
          await _log(
            history.id,
            'info',
            'Compressão concluída',
            step: LogStepConstants.compressionDone,
          );
        } else {
          final failure = compressionResult.exceptionOrNull()!;
          final failureMessage = failure.toString();

          LoggerService.error('Falha na compressão: $failureMessage', failure);
          await _log(
            history.id,
            'error',
            'Falha na compressão: $failureMessage',
            step: LogStepConstants.compressionFailed,
          );

          return rd.Failure(failure);
        }
      }

      if (schedule.postBackupScript != null &&
          schedule.postBackupScript!.trim().isNotEmpty) {
        await _log(
          history.id,
          'info',
          'Executando script SQL pós-backup',
          step: LogStepConstants.scriptPostBackup,
        );

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
      final totalDuration = finishedAt.difference(history.startedAt);
      final metrics = _buildMetrics(
        backupExecutionResult: backupExecutionResult,
        compressionDuration: compressionDuration,
        totalDuration: totalDuration,
        finalFileSize: fileSize,
        backupType: backupType,
        scheduleBackupType: schedule.backupType,
        databaseType: schedule.databaseType,
        history: history,
        sybaseLogPreflight: sybaseLogPreflight,
      );
      history = history.copyWith(
        backupPath: backupPath,
        fileSize: fileSize,
        status: BackupStatus.success,
        finishedAt: finishedAt,
        durationSeconds: totalDuration.inSeconds,
        metrics: metrics,
      );

      final updateResult = await _backupHistoryRepository
          .updateHistoryAndLogIfRunning(
            history: history,
            logStep: LogStepConstants.backupSuccess,
            logLevel: LogLevel.info,
            logMessage: 'Backup finalizado com sucesso',
          );
      updateResult.fold(
        (_) {},
        (e) => LoggerService.warning('Erro ao atualizar histórico e log: $e'),
      );

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

      final updateResult = await _backupHistoryRepository
          .updateHistoryAndLogIfRunning(
            history: history,
            logStep: LogStepConstants.backupError,
            logLevel: LogLevel.error,
            logMessage: 'Erro no backup: $e',
          );
      updateResult.fold(
        (_) {},
        (err) =>
            LoggerService.warning('Erro ao atualizar histórico e log: $err'),
      );

      await _notificationService.notifyBackupComplete(history);

      return rd.Failure(
        BackupFailure(
          message: 'Erro ao executar backup: $e',
          code: FailureCodes.backupFailed,
          originalError: e,
        ),
      );
    }
  }

  Future<void> _log(
    String historyId,
    String levelStr,
    String message, {
    String? step,
  }) async {
    if (step != null) {
      final level = _logLevelFromString(levelStr);
      final result = await _backupLogRepository.createIdempotent(
        backupHistoryId: historyId,
        step: step,
        level: level,
        category: LogCategory.execution,
        message: message,
      );
      result.fold(
        (_) {},
        (e) => LoggerService.warning('Erro ao gravar log idempotente: $e'),
      );
      return;
    }

    final level = _logLevelFromString(levelStr);
    final log = BackupLog(
      backupHistoryId: historyId,
      level: level,
      category: LogCategory.execution,
      message: message,
    );
    await _backupLogRepository.create(log);
  }

  LogLevel _logLevelFromString(String levelStr) {
    switch (levelStr) {
      case 'info':
        return LogLevel.info;
      case 'warning':
        return LogLevel.warning;
      case 'error':
        return LogLevel.error;
      default:
        return LogLevel.info;
    }
  }

  BackupMetrics _buildMetrics({
    required BackupExecutionResult backupExecutionResult,
    required Duration compressionDuration,
    required Duration totalDuration,
    required int finalFileSize,
    required BackupType backupType,
    BackupType? scheduleBackupType,
    DatabaseType? databaseType,
    BackupHistory? history,
    SybaseLogBackupPreflightResult? sybaseLogPreflight,
  }) {
    final base = backupExecutionResult.metrics;
    var mergedSybaseOptions = base?.sybaseOptions != null
        ? Map<String, dynamic>.from(base!.sybaseOptions!)
        : null;

    if (databaseType == DatabaseType.sybase &&
        scheduleBackupType != null &&
        scheduleBackupType != backupType) {
      mergedSybaseOptions ??= {};
      mergedSybaseOptions['requestedBackupType'] = scheduleBackupType.name;
    }

    if (databaseType == DatabaseType.sybase) {
      mergedSybaseOptions ??= {};
      if (backupType == BackupType.log &&
          sybaseLogPreflight?.baseFull != null &&
          sybaseLogPreflight?.nextLogSequence != null) {
        final baseFull = sybaseLogPreflight!.baseFull!;
        mergedSybaseOptions['baseFullId'] = baseFull.id;
        mergedSybaseOptions['chainStartAt'] =
            (baseFull.finishedAt ?? baseFull.startedAt).toIso8601String();
        mergedSybaseOptions['logSequence'] = sybaseLogPreflight.nextLogSequence;
      } else if ((backupType == BackupType.full ||
              backupType == BackupType.fullSingle) &&
          history != null) {
        mergedSybaseOptions['baseFullId'] = history.id;
        mergedSybaseOptions['chainStartAt'] =
            history.startedAt.toIso8601String();
      }
    }

    if (base != null) {
      return base.copyWith(
        compressionDuration: compressionDuration,
        totalDuration: totalDuration,
        backupSizeBytes: finalFileSize,
        backupSpeedMbPerSec: _speedMbPerSec(finalFileSize, totalDuration),
        sybaseOptions: mergedSybaseOptions ?? base.sybaseOptions,
      );
    }
    const defaultFlags = BackupFlags(
      compression: false,
      verifyPolicy: 'none',
      stripingCount: 1,
      withChecksum: false,
      stopOnError: true,
    );
    return BackupMetrics(
      totalDuration: totalDuration,
      backupDuration: backupExecutionResult.duration,
      verifyDuration: Duration.zero,
      compressionDuration: compressionDuration,
      backupSizeBytes: finalFileSize,
      backupSpeedMbPerSec: _speedMbPerSec(finalFileSize, totalDuration),
      backupType: backupType.name,
      flags: defaultFlags,
    );
  }

  static SybaseLogBackupMode _effectiveSybaseLogMode(
    SybaseBackupOptions? options,
    bool truncateLog,
  ) {
    if (options?.logBackupMode != null) return options!.logBackupMode!;
    return truncateLog ? SybaseLogBackupMode.truncate : SybaseLogBackupMode.only;
  }

  double _speedMbPerSec(int sizeBytes, Duration duration) {
    if (duration.inSeconds <= 0) return 0;
    final sizeMb = sizeBytes / 1024 / 1024;
    return sizeMb / duration.inSeconds;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
