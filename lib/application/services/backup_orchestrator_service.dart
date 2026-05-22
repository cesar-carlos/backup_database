import 'package:backup_database/application/services/strategies/strategies.dart';
import 'package:backup_database/core/constants/backup_constants.dart';
import 'package:backup_database/core/constants/log_step_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/logging/log_context.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_backup_cancellation_service.dart';
import 'package:backup_database/domain/services/i_backup_compression_orchestrator.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_backup_script_orchestrator.dart';
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';
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
    required IFirebirdConfigRepository firebirdConfigRepository,
    required IBackupHistoryRepository backupHistoryRepository,
    required IBackupLogRepository backupLogRepository,
    required ISqlServerBackupService sqlServerBackupService,
    required ISybaseBackupService sybaseBackupService,
    required IPostgresBackupService postgresBackupService,
    required IFirebirdBackupService firebirdBackupService,
    required IBackupCompressionOrchestrator compressionOrchestrator,
    required IBackupScriptOrchestrator scriptOrchestrator,
    required ISqlScriptExecutionService sqlScriptExecutionService,
    required INotificationService notificationService,
    required IBackupProgressNotifier progressNotifier,
    required GetDatabaseConfig getDatabaseConfig,
    required ValidateBackupDirectory validateBackupDirectory,
    required ValidateSybaseLogBackupPreflight validateSybaseLogBackupPreflight,
    required IStorageChecker storageChecker,
    IBackupCancellationService? cancellationService,
    Map<DatabaseType, IDatabaseBackupStrategy>? strategies,
  }) : _cancellationService = cancellationService,
       _strategies =
           strategies ??
           _buildDefaultStrategies(
             sqlServerBackupService: sqlServerBackupService,
             sybaseBackupService: sybaseBackupService,
             postgresBackupService: postgresBackupService,
             firebirdBackupService: firebirdBackupService,
             validateSybaseLogBackupPreflight: validateSybaseLogBackupPreflight,
           ),
       _sqlServerConfigRepository = sqlServerConfigRepository,
       _sybaseConfigRepository = sybaseConfigRepository,
       _postgresConfigRepository = postgresConfigRepository,
       _firebirdConfigRepository = firebirdConfigRepository,
       _backupHistoryRepository = backupHistoryRepository,
       _backupLogRepository = backupLogRepository,
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
  final IFirebirdConfigRepository _firebirdConfigRepository;
  final IBackupHistoryRepository _backupHistoryRepository;
  final IBackupLogRepository _backupLogRepository;
  final IBackupCompressionOrchestrator _compressionOrchestrator;
  final IBackupScriptOrchestrator _scriptOrchestrator;
  final ISqlScriptExecutionService _sqlScriptExecutionService;
  final INotificationService _notificationService;
  final IBackupProgressNotifier _progressNotifier;
  final GetDatabaseConfig _getDatabaseConfig;
  final ValidateBackupDirectory _validateBackupDirectory;
  // Mantido como referência opcional para o caso de testes/extensões que
  // queiram chamar o preflight diretamente; o uso normal vive nas rules
  // `SybaseLogBackupPreflightRule` via `SybaseBackupStrategyFactory`.
  // ignore: unused_field
  final ValidateSybaseLogBackupPreflight _validateSybaseLogBackupPreflight;
  final IStorageChecker _storageChecker;
  // Opcional para preservar compatibilidade com testes que constroem o
  // orchestrator sem o serviço de cancelamento. Em produção é registrado
  // via DI e exposto através de [cancelByHistoryId].
  final IBackupCancellationService? _cancellationService;

  /// Mapa de estratégias por SGBD. Quando não fornecido pelo construtor,
  /// é montado automaticamente com as três estratégias padrão a partir
  /// dos serviços de infraestrutura injetados (preserva compatibilidade
  /// com chamadas existentes do construtor sem o parâmetro `strategies`).
  final Map<DatabaseType, IDatabaseBackupStrategy> _strategies;

  static Map<DatabaseType, IDatabaseBackupStrategy> _buildDefaultStrategies({
    required ISqlServerBackupService sqlServerBackupService,
    required ISybaseBackupService sybaseBackupService,
    required IPostgresBackupService postgresBackupService,
    required IFirebirdBackupService firebirdBackupService,
    required ValidateSybaseLogBackupPreflight validateSybaseLogBackupPreflight,
  }) {
    return {
      DatabaseType.sqlServer: SqlServerBackupStrategyFactory.create(
        sqlServerBackupService,
      ),
      DatabaseType.sybase: SybaseBackupStrategyFactory.create(
        service: sybaseBackupService,
        validatePreflight: validateSybaseLogBackupPreflight,
      ),
      DatabaseType.postgresql: PostgresBackupStrategyFactory.create(
        postgresBackupService,
      ),
      DatabaseType.firebird: FirebirdBackupStrategy(firebirdBackupService),
    };
  }

  Future<rd.Result<BackupHistory>> executeBackup({
    required Schedule schedule,
    required String outputDirectory,
    bool notifyOnComplete = true,
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
            schedule.databaseType != DatabaseType.firebird &&
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

    // Validate minimum free disk space. Quando conseguimos estimar o
    // tamanho do banco (via SGBD), usamos `tamanho × safetyFactor`. Caso
    // contrário, caímos no mínimo configurado em [BackupConstants].
    final spaceResult = await _storageChecker.checkSpace(typeOutputDirectory);
    if (spaceResult.isError()) {
      final failure = spaceResult.exceptionOrNull()!;
      LoggerService.error('Free space check failed', failure);
      return rd.Failure(failure);
    }
    final spaceInfo = spaceResult.getOrNull()!;
    final requiredBytes = await _estimateRequiredSpaceBytes(schedule);
    if (!spaceInfo.hasEnoughSpace(requiredBytes)) {
      final errorMessage =
          'Espaço livre insuficiente no destino do backup. '
          'Disponível: ${ByteFormat.format(spaceInfo.freeBytes)}, '
          'Necessário (estimado): ${ByteFormat.format(requiredBytes)}';
      LoggerService.error(errorMessage);
      return rd.Failure(ValidationFailure(message: errorMessage));
    }

    LoggerService.info(
      'Diretório de backup por tipo: $typeOutputDirectory '
      '(Tipo: ${getBackupTypeDisplayName(backupType)})',
    );

    var history = BackupHistory(
      runId: LogContext.runId,
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

    // Tag canônica usada por todos os serviços de backup para permitir
    // cancelamento granular via [IBackupCancellationService.cancelByHistoryId].
    final cancelTag = 'backup-${history.id}';

    // Expõe o historyId para o progress notifier; a UI usa esse id para
    // chamar `cancelByHistoryId` no botão de cancelar.
    _safeNotifierCall(
      () => _progressNotifier.setCurrentHistoryId(history.id),
      'Falha ao publicar historyId no progress notifier',
    );

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
        final configFailure = ConfigNotFoundFailure(
          message:
              'Configuration not found for ${schedule.databaseType.name} '
              '(id: ${schedule.databaseConfigId})',
          code: FailureCodes.configNotFound,
          originalError: failure,
        );
        return _failRunningHistory(
          history: history,
          errorMessage: configFailure.message,
          logStep: LogStepConstants.backupError,
          failure: configFailure,
          notifyOnComplete: notifyOnComplete,
        );
      }

      // Despacho via Strategy: cada SGBD encapsula seus pré-requisitos,
      // cast de opções e a chamada ao serviço de infraestrutura. Adicionar
      // suporte a um novo SGBD = registrar uma nova estratégia em DI
      // (Open/Closed Principle).
      final strategy = _strategies[schedule.databaseType];
      if (strategy == null) {
        const errorMessage = 'Unsupported database type';
        return _failRunningHistory(
          history: history,
          errorMessage:
              '$errorMessage: ${schedule.databaseType}',
          logStep: LogStepConstants.backupError,
          failure: ValidationFailure(
            message:
                '$errorMessage: ${schedule.databaseType}',
          ),
          notifyOnComplete: notifyOnComplete,
        );
      }

      final BackupExecutionResult backupExecutionResult;
      final strategyResult = await strategy.execute(
        schedule: schedule,
        databaseConfig: configResult.getOrNull()!,
        outputDirectory: typeOutputDirectory,
        backupType: backupType,
        cancelTag: cancelTag,
      );
      if (strategyResult.isError()) {
        final failure = strategyResult.exceptionOrNull()!;
        final failureMessage = _failureMessage(failure);
        return _failRunningHistory(
          history: history,
          errorMessage: failureMessage,
          logStep: LogStepConstants.backupError,
          failure: _asFailure(failure),
          notifyOnComplete: notifyOnComplete,
        );
      }
      backupExecutionResult = strategyResult.getOrNull()!;
      // O preflight Sybase vive em `SybaseLogBackupPreflightRule` e o
      // enriquecimento de métricas em `SybaseChainMetadataEnricher`.
      // Mantemos `sybaseLogPreflight` como `null` aqui para preservar a
      // assinatura do `_buildMetrics` (parâmetro legado).
      sybaseLogPreflight = null;

      backupPath = backupExecutionResult.backupPath;
      fileSize = backupExecutionResult.fileSize;
      // Quando a infraestrutura informa que o tipo executado é diferente
      // do solicitado (ex.: PG incremental → full por falta de base),
      // ajustamos o tipo persistido para evitar histórico inconsistente.
      final executedBackupType =
          backupExecutionResult.executedBackupType ?? backupType;
      if (executedBackupType != backupType) {
        LoggerService.warning(
          'Backup solicitado como ${backupType.name} foi executado como '
          '${executedBackupType.name} (fallback automático). '
          'O histórico será gravado com o tipo realmente executado.',
        );
      }

      await _log(
        history.id,
        'info',
        'Backup do banco concluído',
        step: LogStepConstants.backupDbDone,
      );

      _safeNotifierCall(
        () => _progressNotifier.updateProgress(
          step: 'Executando backup',
          message: 'Backup do banco concluído',
          progress: 0.5,
        ),
        'Erro ao atualizar progresso',
      );

      // Quando o backup terminou com payload vazio (caso típico do
      // pg_receivewal sem novos segmentos), pular compressão evita falha
      // duplicada e marca o resultado como warning.
      final hasPayload = fileSize > 0;
      final isEmptyLogBackup =
          !hasPayload && executedBackupType == BackupType.log;

      var compressionDuration = Duration.zero;
      if (isEmptyLogBackup) {
        await _log(
          history.id,
          'info',
          'Sem novos segmentos de log para capturar; compressão e '
              'pós-script ignorados.',
          step: LogStepConstants.compressionSkipped,
        );
      } else if (schedule.compressionFormat != CompressionFormat.none) {
        await _log(
          history.id,
          'info',
          'Iniciando compressão',
          step: LogStepConstants.compressionStarted,
        );

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
          compressionDuration = result.duration;
          await _log(
            history.id,
            'info',
            'Compressão concluída',
            step: LogStepConstants.compressionDone,
          );
        } else {
          final failure = compressionResult.exceptionOrNull()!;
          final failureMessage = _failureMessage(failure);

          LoggerService.error('Falha na compressão: $failureMessage', failure);
          await _log(
            history.id,
            'error',
            'Falha na compressão: $failureMessage',
            step: LogStepConstants.compressionFailed,
          );

          return _failRunningHistory(
            history: history,
            errorMessage: 'Falha na compressão: $failureMessage',
            logStep: LogStepConstants.compressionFailed,
            failure: _asFailure(failure),
            notifyOnComplete: notifyOnComplete,
          );
        }
      }

      if (!isEmptyLogBackup &&
          schedule.postBackupScript != null &&
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
          firebirdConfigRepository: _firebirdConfigRepository,
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
        backupType: executedBackupType,
        scheduleBackupType: schedule.backupType,
        databaseType: schedule.databaseType,
        history: history,
        sybaseLogPreflight: sybaseLogPreflight,
      );
      // Backup vazio de log é tratado como warning (sem novos dados),
      // diferente de error e diferente de success com payload.
      final finalStatus = isEmptyLogBackup
          ? BackupStatus.warning
          : BackupStatus.success;
      // Bug histórico: este ternário tinha `LogStepConstants.backupSuccess`
      // nos dois ramos — branches idênticas, sintoma de copy/paste. Como
      // ambos os caminhos representam "backup terminou OK" (apenas o
      // status final difere), mantemos a semântica unificada e removemos
      // o ternário enganador.
      const logStep = LogStepConstants.backupSuccess;
      final logMessage = isEmptyLogBackup
          ? 'Backup finalizado sem novos dados (warning)'
          : 'Backup finalizado com sucesso';

      history = history.copyWith(
        backupPath: backupPath,
        fileSize: fileSize,
        backupType: executedBackupType.name,
        status: finalStatus,
        finishedAt: finishedAt,
        durationSeconds: totalDuration.inSeconds,
        metrics: metrics,
      );

      final updateResult = await _backupHistoryRepository
          .updateHistoryAndLogIfRunning(
            history: history,
            logStep: logStep,
            logLevel: isEmptyLogBackup ? LogLevel.warning : LogLevel.info,
            logMessage: logMessage,
          );
      updateResult.fold(
        (_) {},
        (e) => LoggerService.warning('Erro ao atualizar histórico e log: $e'),
      );

      if (notifyOnComplete) {
        await _safeNotifyComplete(history);
      }

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

      if (notifyOnComplete) {
        await _safeNotifyComplete(history);
      }

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
    final level = LogLevel.fromString(levelStr);
    if (step != null) {
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

    final log = BackupLog(
      backupHistoryId: historyId,
      level: level,
      category: LogCategory.execution,
      message: message,
    );
    final result = await _backupLogRepository.create(log);
    // Antes este `await` ignorava o `Result` retornado; falhas de I/O na
    // tabela de logs ficavam invisíveis, dificultando diagnóstico de
    // backups que perdiam logs intermediários sem motivo aparente.
    result.fold(
      (_) {},
      (e) => LoggerService.warning(
        'Erro ao gravar log livre (sem step): $e',
      ),
    );
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

    // Quando o tipo executado difere do solicitado (ex.: PG incremental
    // que caiu para FULL), gravamos `requestedBackupType` em
    // `sybaseOptions` para que a UI possa exibir a divergência. Apesar do
    // nome do campo, o mapa já é genérico (só virou `sybaseOptions` por
    // razões históricas) e usado por todas as bases.
    if (scheduleBackupType != null && scheduleBackupType != backupType) {
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
        mergedSybaseOptions['chainStartAt'] = history.startedAt
            .toIso8601String();
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

  double _speedMbPerSec(int sizeBytes, Duration duration) =>
      ByteFormat.speedMbPerSecFromDuration(sizeBytes, duration);

  /// Estima o espaço em bytes necessário para um backup do [schedule].
  /// Tenta consultar o tamanho real do banco no servidor; em caso de
  /// falha, retorna [BackupConstants.minFreeSpaceForBackupBytes] para não
  /// bloquear o backup por uma checagem opcional.
  Future<int> _estimateRequiredSpaceBytes(Schedule schedule) async {
    const fallback = BackupConstants.minFreeSpaceForBackupBytes;
    try {
      final configResult = await _getDatabaseConfig(
        schedule.databaseConfigId,
        schedule.databaseType,
      );
      if (configResult.isError()) return fallback;

      final strategy = _strategies[schedule.databaseType];
      if (strategy == null) {
        LoggerService.warning(
          'Sem estratégia de backup para ${schedule.databaseType}; '
          'não foi possível estimar tamanho do banco.',
        );
        return fallback;
      }

      final sizeResult = await strategy.getDatabaseSizeBytes(
        databaseConfig: configResult.getOrNull()!,
      );

      if (sizeResult.isError()) {
        LoggerService.warning(
          'Não foi possível estimar tamanho do banco; usando mínimo padrão. '
          'Erro: ${sizeResult.exceptionOrNull()}',
        );
        return fallback;
      }

      final sizeBytes = sizeResult.getOrNull()!;
      final required = (sizeBytes * BackupConstants.backupSpaceSafetyFactor)
          .toInt();
      // Aplica também o piso mínimo para evitar valores absurdamente
      // baixos quando o banco é muito pequeno.
      return required > fallback ? required : fallback;
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao estimar tamanho do banco; usando mínimo padrão. Erro: $e',
      );
      return fallback;
    }
  }

  /// Solicita o cancelamento do backup em execução cujo histórico tem
  /// `id == historyId`. No-op se não há serviço de cancelamento
  /// configurado (cenários de teste).
  void cancelByHistoryId(String historyId) {
    final service = _cancellationService;
    if (service == null) {
      LoggerService.warning(
        'cancelByHistoryId chamado mas IBackupCancellationService '
        'não foi injetado; cancelamento ignorado.',
      );
      return;
    }
    service.cancelByHistoryId(historyId);
  }

  /// Wrapper defensivo para chamadas ao `IBackupProgressNotifier`.
  /// Centraliza o padrão `try { notifier.X(); } catch ...` que antes era
  /// repetido inline em 2 pontos do `executeBackup`. Em failure, registra
  /// como warning sem propagar — atualizar progresso é "best-effort", não
  /// deve abortar o backup.
  void _safeNotifierCall(void Function() action, String errorMessage) {
    try {
      action();
    } on Object catch (e, s) {
      LoggerService.warning(errorMessage, e, s);
    }
  }

  /// Wrapper defensivo para `notifyBackupComplete`. Antes era repetido
  /// com try/catch quase idênticos em 2 pontos (success + error path).
  /// Garante que falha em e-mail nunca derrube o backup propriamente dito.
  Future<void> _safeNotifyComplete(BackupHistory history) async {
    try {
      await _notificationService.notifyBackupComplete(history);
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao enviar notificação de conclusão de backup',
        e,
        s,
      );
    }
  }

  Future<rd.Result<BackupHistory>> _failRunningHistory({
    required BackupHistory history,
    required String errorMessage,
    required String logStep,
    required Failure failure,
    bool notifyOnComplete = true,
  }) async {
    final finishedAt = DateTime.now();
    final failedHistory = history.copyWith(
      status: BackupStatus.error,
      errorMessage: errorMessage,
      finishedAt: finishedAt,
      durationSeconds: finishedAt.difference(history.startedAt).inSeconds,
    );
    final updateResult = await _backupHistoryRepository
        .updateHistoryAndLogIfRunning(
          history: failedHistory,
          logStep: logStep,
          logLevel: LogLevel.error,
          logMessage: errorMessage,
        );
    updateResult.fold(
      (_) {},
      (e) => LoggerService.warning(
        'Erro ao atualizar histórico após falha intermediária: $e',
      ),
    );
    if (notifyOnComplete) {
      await _safeNotifyComplete(failedHistory);
    }
    return rd.Failure(failure);
  }

  String _failureMessage(Object? failure, {String fallback = 'Erro'}) =>
      failureUserMessage(failure, fallback: fallback);

  /// Converte `Object` (que sai de `Result.exceptionOrNull()`) em
  /// `Failure` de forma segura. Antes a strategy result usava
  /// `failure is Failure ? failure : BackupFailure(message: '$failure')`
  /// inline; centralizamos para garantir consistência se outros pontos
  /// do orchestrator precisarem do mesmo wrap.
  Failure _asFailure(Object failure) {
    if (failure is Failure) return failure;
    return BackupFailure(
      message: _failureMessage(failure),
      originalError: failure,
    );
  }
}
