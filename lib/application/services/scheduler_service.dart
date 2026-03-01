import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/services/backup_orchestrator_service.dart';
import 'package:backup_database/core/constants/backup_constants.dart';
import 'package:backup_database/core/constants/log_step_constants.dart';
import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/logging/log_context.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType, Schedule;
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/i_backup_cleanup_service.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_destination_orchestrator.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:backup_database/domain/services/i_schedule_calculator.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_storage_checker.dart';
import 'package:backup_database/domain/services/i_transfer_staging_service.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:uuid/uuid.dart';

class SchedulerService implements ISchedulerService {
  SchedulerService({
    required IScheduleRepository scheduleRepository,
    required IBackupDestinationRepository destinationRepository,
    required IBackupHistoryRepository backupHistoryRepository,
    required BackupOrchestratorService backupOrchestratorService,
    required IDestinationOrchestrator destinationOrchestrator,
    required IBackupCleanupService cleanupService,
    required INotificationService notificationService,
    required IScheduleCalculator scheduleCalculator,
    required IStorageChecker storageChecker,
    required IBackupProgressNotifier progressNotifier,
    required ILicensePolicyService licensePolicyService,
    ITransferStagingService? transferStagingService,
    IMetricsCollector? metricsCollector,
  }) : _scheduleRepository = scheduleRepository,
       _destinationRepository = destinationRepository,
       _backupHistoryRepository = backupHistoryRepository,
       _backupOrchestratorService = backupOrchestratorService,
       _destinationOrchestrator = destinationOrchestrator,
       _cleanupService = cleanupService,
       _notificationService = notificationService,
       _scheduleCalculator = scheduleCalculator,
       _storageChecker = storageChecker,
       _progressNotifier = progressNotifier,
       _licensePolicyService = licensePolicyService,
       _transferStagingService = transferStagingService,
       _metricsCollector = metricsCollector;

  final IScheduleRepository _scheduleRepository;
  final IBackupDestinationRepository _destinationRepository;
  final IBackupHistoryRepository _backupHistoryRepository;
  final BackupOrchestratorService _backupOrchestratorService;
  final IDestinationOrchestrator _destinationOrchestrator;
  final IBackupCleanupService _cleanupService;
  final INotificationService _notificationService;
  final IScheduleCalculator _scheduleCalculator;
  final IStorageChecker _storageChecker;
  final IBackupProgressNotifier _progressNotifier;
  final ILicensePolicyService _licensePolicyService;
  final ITransferStagingService? _transferStagingService;
  final IMetricsCollector? _metricsCollector;

  Timer? _checkTimer;
  bool _isRunning = false;
  final Set<String> _executingSchedules = {};
  final Set<String> _cancelRequestedSchedules = {};

  @override
  Future<void> start() async {
    if (_isRunning) return;

    LoggerService.info('Iniciando serviço de agendamento');
    _isRunning = true;

    await _updateAllNextRuns();

    _checkTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkSchedules(),
    );

    LoggerService.info('Serviço de agendamento iniciado');
  }

  @override
  void stop() {
    LoggerService.info('Parando serviço de agendamento');
    _isRunning = false;
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  Future<void> _updateAllNextRuns() async {
    final result = await _scheduleRepository.getEnabled();

    result.fold(
      (schedules) async {
        for (final schedule in schedules) {
          final nextRunAt = _scheduleCalculator.getNextRunTime(schedule);
          if (nextRunAt != null) {
            LoggerService.info(
              'Atualizando schedule ${schedule.name}: '
              'nextRunAt atual = ${schedule.nextRunAt}, '
              'novo nextRunAt = $nextRunAt',
            );
            await _scheduleRepository.update(
              schedule.copyWith(nextRunAt: nextRunAt),
            );
          }
        }
        LoggerService.info('${schedules.length} schedules atualizados');
      },
      (exception) {
        final failure = exception as Failure;
        LoggerService.error('Erro ao atualizar schedules: ${failure.message}');
      },
    );
  }

  Future<void> _checkSchedules() async {
    if (!_isRunning) return;
    if (_executingSchedules.isNotEmpty) return;

    final now = DateTime.now();
    final result = await _scheduleRepository.getEnabledDueForExecution(now);

    result.fold((schedules) async {
      if (schedules.isEmpty) return;

      final schedule = schedules.first;
      final nextRunAt = _scheduleCalculator.getNextRunTime(schedule);
      if (nextRunAt != null) {
        await _scheduleRepository.update(
          schedule.copyWith(nextRunAt: nextRunAt),
        );
      }

      unawaited(_runScheduleWithLock(schedule));
    }, (failure) => null);
  }

  Future<rd.Result<void>> _executeScheduledBackup(Schedule schedule) async {
    LoggerService.info(
      'Executando backup agendado: ${schedule.name} '
      '(nextRunAt: ${schedule.nextRunAt}, now: ${DateTime.now()})',
    );

    late String tempBackupPath;
    var shouldDeleteTempFile = false;
    final runId = '${schedule.id}_${const Uuid().v4()}';

    try {
      _licensePolicyService.setRunContext(runId);
      LogContext.setContext(runId: runId, scheduleId: schedule.id);

      final canceledAtStart = await _failIfCancellationRequested(
        schedule: schedule,
      );
      if (canceledAtStart != null) {
        return canceledAtStart;
      }

      final destinations = await _getDestinations(schedule.destinationIds);
      if (destinations.length != schedule.destinationIds.length) {
        final foundIds = destinations.map((d) => d.id).toSet();
        final missingIds = schedule.destinationIds
            .where((id) => !foundIds.contains(id))
            .toList();

        final errorMessage =
            'Destinos vinculados ao agendamento nao foram encontrados: '
            '${missingIds.join(", ")}';
        LoggerService.error(errorMessage);
        return rd.Failure(ValidationFailure(message: errorMessage));
      }

      if (schedule.backupFolder.isEmpty) {
        final errorMessage =
            'Pasta de backup não configurada para o agendamento: '
            '${schedule.name}';
        LoggerService.error(errorMessage);
        return rd.Failure(ValidationFailure(message: errorMessage));
      }

      final backupDir = Directory(schedule.backupFolder);
      if (!await backupDir.exists()) {
        try {
          await backupDir.create(recursive: true);
        } on Object catch (e) {
          final errorMessage =
              'Erro ao criar pasta de backup: ${schedule.backupFolder}';
          LoggerService.error(errorMessage, e);
          return rd.Failure(ValidationFailure(message: errorMessage));
        }
      }

      final hasPermission = await _checkWritePermission(backupDir);
      if (!hasPermission) {
        final errorMessage =
            'Sem permissão de escrita na pasta de backup: '
            '${schedule.backupFolder}';
        LoggerService.error(errorMessage);
        return rd.Failure(ValidationFailure(message: errorMessage));
      }

      final spaceCheckResult = await _checkFreeSpace(backupDir, schedule);
      if (spaceCheckResult.isError()) {
        return spaceCheckResult;
      }

      final outputDirectory = backupDir.path;
      shouldDeleteTempFile = true;
      LoggerService.info(
        'Usando pasta temporária de backup: $outputDirectory',
      );

      if (outputDirectory.isEmpty) {
        final errorMessage =
            'Caminho de saída do backup está vazio para o agendamento: '
            '${schedule.name}';
        LoggerService.error(errorMessage);
        return rd.Failure(ValidationFailure(message: errorMessage));
      }

      final policyResult = await _licensePolicyService
          .validateExecutionCapabilities(schedule, destinations);
      if (policyResult.isError()) {
        final failure = policyResult.exceptionOrNull()!;
        final message = failure is Failure
            ? failure.message
            : failure.toString();
        LoggerService.error(
          'Execução bloqueada por licença: $message',
          failure,
        );
        return rd.Failure(failure);
      }

      final backupResult = await _backupOrchestratorService.executeBackup(
        schedule: schedule,
        outputDirectory: outputDirectory,
      );

      if (backupResult.isError()) {
        try {
          final error = backupResult.exceptionOrNull()!;
          final errorMessage = error is Failure
              ? error.message
              : error.toString();
          _progressNotifier.failBackup(errorMessage);
        } on Object catch (e, s) {
          LoggerService.warning('Erro ao atualizar progresso failBackup', e, s);
        }
        return rd.Failure(backupResult.exceptionOrNull()!);
      }

      final backupHistory = backupResult.getOrNull()!;
      tempBackupPath = backupHistory.backupPath;

      final canceledAfterBackup = await _failIfCancellationRequested(
        schedule: schedule,
        backupHistory: backupHistory,
      );
      if (canceledAfterBackup != null) {
        return canceledAfterBackup;
      }

      final backupFile = File(backupHistory.backupPath);
      if (!await backupFile.exists()) {
        final errorMessage =
            'Arquivo de backup não existe: ${backupHistory.backupPath}';
        LoggerService.error(errorMessage);
        final finishedAt = DateTime.now();
        final failedHistory = backupHistory.copyWith(
          status: BackupStatus.error,
          errorMessage: errorMessage,
          finishedAt: finishedAt,
          durationSeconds: finishedAt
              .difference(backupHistory.startedAt)
              .inSeconds,
        );
        final updateResult = await _backupHistoryRepository
            .updateHistoryAndLogIfRunning(
              history: failedHistory,
              logStep: LogStepConstants.backupFileNotFound,
              logLevel: LogLevel.error,
              logMessage: errorMessage,
            );
        updateResult.fold(
          (_) {},
          (e) => LoggerService.warning('Erro ao atualizar histórico e log: $e'),
        );

        try {
          _progressNotifier.failBackup(errorMessage);
        } on Object catch (e, s) {
          LoggerService.warning('Erro ao atualizar progresso failBackup', e, s);
        }

        return rd.Failure(BackupFailure(message: errorMessage));
      }

      final hasDestinations = destinations.isNotEmpty;

      if (hasDestinations) {
        try {
          _progressNotifier.updateProgress(
            step: 'Enviando para destino',
            message: 'Enviando para destinos...',
            progress: 0.85,
          );
        } on Object catch (e, s) {
          LoggerService.warning('Erro ao atualizar progresso', e, s);
        }
      }

      final uploadErrors = <String>[];
      var hasCriticalUploadError = false;

      final canceledBeforeUpload = await _failIfCancellationRequested(
        schedule: schedule,
        backupHistory: backupHistory,
      );
      if (canceledBeforeUpload != null) {
        return canceledBeforeUpload;
      }

      if (!await backupFile.exists()) {
        final errorMessage =
            'Arquivo de backup não existe: ${backupHistory.backupPath}';
        LoggerService.error(errorMessage);
        final finishedAt = DateTime.now();
        final failedHistory = backupHistory.copyWith(
          status: BackupStatus.error,
          errorMessage: errorMessage,
          finishedAt: finishedAt,
          durationSeconds: finishedAt
              .difference(backupHistory.startedAt)
              .inSeconds,
        );
        final updateResult = await _backupHistoryRepository
            .updateHistoryAndLogIfRunning(
              history: failedHistory,
              logStep: LogStepConstants.backupFileNotFound,
              logLevel: LogLevel.error,
              logMessage: errorMessage,
            );
        updateResult.fold(
          (_) {},
          (e) => LoggerService.warning('Erro ao atualizar histórico e log: $e'),
        );
        try {
          _progressNotifier.failBackup(errorMessage);
        } on Object catch (e, s) {
          LoggerService.warning('Erro ao atualizar progresso failBackup', e, s);
        }
        return rd.Failure(BackupFailure(message: errorMessage));
      }

      final uploadStopwatch = Stopwatch()..start();
      final backupIdForPath = schedule.databaseType == DatabaseType.sybase
          ? backupHistory.id
          : null;
      final sendResults = await _destinationOrchestrator
          .uploadToAllDestinations(
            sourceFilePath: backupHistory.backupPath,
            destinations: destinations,
            isCancelled: () => _cancelRequestedSchedules.contains(schedule.id),
            backupId: backupIdForPath,
            onProgress: (double p, [String? stepOverride]) {
              try {
                _progressNotifier.updateProgress(
                  step: stepOverride ?? 'Enviando para destino',
                  message: '${(p * 100).toInt()}%',
                  progress: 0.85 + p * 0.10,
                );
              } on Object catch (e, s) {
                LoggerService.debug('Erro ao atualizar progresso: $e', e, s);
              }
            },
          );
      uploadStopwatch.stop();
      final uploadDuration = uploadStopwatch.elapsed;
      _metricsCollector?.recordHistogram(
        ObservabilityMetrics.destinationUploadDurationMs,
        uploadDuration.inMilliseconds.toDouble(),
      );

      try {
        _progressNotifier.updateProgress(
          step: 'Enviando para destino',
          message: 'Upload para destinos concluído.',
          progress: 0.95,
        );
      } on Object catch (e, s) {
        LoggerService.warning('Erro ao atualizar progresso', e, s);
      }

      for (var index = 0; index < sendResults.length; index++) {
        final destination = destinations[index];
        final sendResult = sendResults[index];
        sendResult.fold((_) {}, (failure) {
          _metricsCollector?.incrementCounter(
            ObservabilityMetrics.destinationUploadFailureTotal,
          );
          final failureMessage = failure is Failure
              ? failure.message
              : failure.toString();
          final errorMessage =
              'Falha ao enviar para ${destination.name}: $failureMessage';
          uploadErrors.add(errorMessage);
          LoggerService.error(errorMessage, failure);
          hasCriticalUploadError = true;
        });
      }

      if (hasCriticalUploadError) {
        final errorMessage = uploadErrors.join('\n');
        final finishedAt = DateTime.now();
        final failedHistory = backupHistory.copyWith(
          status: BackupStatus.error,
          errorMessage:
              'Backup concluído na pasta temporária, mas falhou ao enviar '
              'para destinos:\n$errorMessage',
          finishedAt: finishedAt,
          durationSeconds: finishedAt
              .difference(backupHistory.startedAt)
              .inSeconds,
        );
        final updateResult = await _backupHistoryRepository
            .updateHistoryAndLogIfRunning(
              history: failedHistory,
              logStep: LogStepConstants.uploadFailed,
              logLevel: LogLevel.error,
              logMessage:
                  'Falha ao enviar backup para destinos:\n$errorMessage',
            );
        updateResult.fold(
          (_) {},
          (e) => LoggerService.warning('Erro ao atualizar histórico e log: $e'),
        );

        final notifyResult = await _notificationService.notifyBackupComplete(
          failedHistory,
        );
        notifyResult.fold(
          (sent) {
            if (sent) {
              LoggerService.info('Notificação de erro enviada por email');
            } else {
              LoggerService.warning(
                'Notificação de erro não foi enviada '
                '(email desabilitado ou configuração inválida)',
              );
            }
          },
          (failure) {
            LoggerService.error(
              'Erro ao enviar notificação por email',
              failure,
            );
          },
        );

        final failure = BackupFailure(
          message: 'Falha ao enviar backup para destinos:\n$errorMessage',
          code: FailureCodes.uploadFailed,
        );
        LoggerService.error(
          'Backup marcado como erro devido a falhas no upload',
          failure,
        );

        try {
          _progressNotifier.failBackup(errorMessage);
        } on Object catch (e, s) {
          LoggerService.warning('Erro ao atualizar progresso failBackup', e, s);
        }

        return rd.Failure(failure);
      }

      if (uploadErrors.isNotEmpty) {
        final warningMessage =
            'O backup foi concluído, mas houve avisos:\n\n'
            '${uploadErrors.join('\n')}';

        await _notificationService.sendWarning(
          databaseName: schedule.name,
          message: warningMessage,
        );
      }

      if (hasDestinations) {
        LoggerService.info(
          'Uploads para destinos concluídos, enviando notificação por e-mail',
        );
      }
      await _notificationService.notifyBackupComplete(backupHistory);

      // Copiar para staging ANTES de deletar o arquivo temporário
      // para que o cliente possa baixar o arquivo
      String? stagingRelativePath;
      if (_transferStagingService != null) {
        LoggerService.info(
          'Copiando backup para staging: ${backupHistory.backupPath} (scheduleId: ${schedule.id})',
        );
        stagingRelativePath = await _transferStagingService.copyToStaging(
          backupHistory.backupPath,
          schedule.id,
        );

        if (stagingRelativePath != null) {
          LoggerService.info(
            'Backup copiado para staging com sucesso: $stagingRelativePath',
          );
        } else {
          LoggerService.warning(
            'Falha ao copiar backup para staging (copyToStaging retornou null)',
          );
        }
      } else {
        LoggerService.warning(
          'TransferStagingService não está disponível. Cliente não poderá baixar o arquivo.',
        );
      }

      if (shouldDeleteTempFile) {
        try {
          final entityType = FileSystemEntity.typeSync(tempBackupPath);

          switch (entityType) {
            case FileSystemEntityType.file:
              final tempFile = File(tempBackupPath);
              if (tempFile.existsSync()) {
                await tempFile.delete();
                LoggerService.info(
                  'Arquivo temporário deletado: $tempBackupPath',
                );
              }
            case FileSystemEntityType.directory:
              final tempDir = Directory(tempBackupPath);
              if (tempDir.existsSync()) {
                await tempDir.delete(recursive: true);
                LoggerService.info(
                  'Diretório temporário deletado: $tempBackupPath',
                );
              }
            default:
              LoggerService.debug(
                'Arquivo temporário não encontrado para exclusão: '
                '$tempBackupPath',
              );
          }
        } on Object catch (e) {
          LoggerService.warning('Erro ao deletar arquivo temporário: $e');
        }
      }

      final now = DateTime.now();
      final scheduleWithLastRun = schedule.copyWith(lastRunAt: now);
      final nextRunAt = _scheduleCalculator.getNextRunTime(scheduleWithLastRun);
      final updatedSchedule = scheduleWithLastRun.copyWith(
        nextRunAt: nextRunAt,
      );
      await _scheduleRepository.update(updatedSchedule);

      LoggerService.info(
        'Próxima execução de ${schedule.name} agendada para: $nextRunAt '
        '(baseado em lastRunAt: $now, tipo: ${schedule.scheduleType})',
      );

      final cleanupStopwatch = Stopwatch()..start();
      await _cleanupService.cleanOldBackups(
        destinations: destinations,
        backupHistoryId: backupHistory.id,
        schedule: schedule,
      );
      cleanupStopwatch.stop();
      final cleanupDuration = cleanupStopwatch.elapsed;

      final updatedMetrics = _mergeUploadAndCleanupMetrics(
        backupHistory.metrics,
        uploadDuration,
        cleanupDuration,
      );
      if (updatedMetrics != null) {
        final historyWithMetrics = backupHistory.copyWith(
          metrics: updatedMetrics,
        );
        final updateResult = await _backupHistoryRepository.update(
          historyWithMetrics,
        );
        updateResult.fold(
          (_) {},
          (e) => LoggerService.warning(
            'Erro ao atualizar métricas de upload/cleanup: $e',
          ),
        );
      }

      LoggerService.info('Backup agendado concluído: ${schedule.name}');

      final backupRunDurationMs = DateTime.now()
          .difference(backupHistory.startedAt)
          .inMilliseconds
          .toDouble();
      _metricsCollector?.recordHistogram(
        ObservabilityMetrics.backupRunDurationMs,
        backupRunDurationMs,
      );

      try {
        // Usar stagingRelativePath se disponível, senão usa backupPath original
        final pathToSend = stagingRelativePath ?? backupHistory.backupPath;

        // Log para diagnosticar problema de backupPath vazio
        LoggerService.info('===== COMPLETANDO BACKUP =====');
        LoggerService.info('stagingRelativePath: $stagingRelativePath');
        LoggerService.info(
          'backupHistory.backupPath: ${backupHistory.backupPath}',
        );
        LoggerService.info('pathToSend: $pathToSend');
        LoggerService.info('pathToSend está vazio? ${pathToSend.isEmpty}');

        if (stagingRelativePath == null) {
          LoggerService.warning(
            'stagingRelativePath é null, usando backupPath original: $pathToSend',
          );
        }

        _progressNotifier.completeBackup(
          message: 'Backup concluído com sucesso!',
          backupPath: pathToSend,
        );

        LoggerService.info(
          'completeBackup chamado com backupPath: "$pathToSend"',
        );
      } on Object catch (e, s) {
        LoggerService.warning(
          'Erro ao atualizar progresso completeBackup',
          e,
          s,
        );
      }

      return const rd.Success(rd.unit);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro no backup agendado', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro no backup agendado: $e',
          code: FailureCodes.backupFailed,
          originalError: e,
        ),
      );
    } finally {
      _licensePolicyService.clearRunContext();
      LogContext.clearContext();
    }
  }

  Future<rd.Result<void>> _runScheduleWithLock(Schedule schedule) async {
    if (_executingSchedules.isNotEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Já existe um backup em execução no servidor.',
          code: FailureCodes.scheduleAlreadyRunning,
        ),
      );
    }

    if (_executingSchedules.contains(schedule.id)) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Este agendamento já está em execução.',
          code: FailureCodes.scheduleAlreadyRunning,
        ),
      );
    }

    _executingSchedules.add(schedule.id);
    try {
      return await _executeScheduledBackup(schedule);
    } finally {
      _executingSchedules.remove(schedule.id);
      _cancelRequestedSchedules.remove(schedule.id);
    }
  }

  Future<rd.Result<void>?> _failIfCancellationRequested({
    required Schedule schedule,
    BackupHistory? backupHistory,
  }) async {
    if (!_cancelRequestedSchedules.contains(schedule.id)) {
      return null;
    }

    const message = 'Backup cancelado pelo usuario.';
    LoggerService.warning(
      'Cancelamento detectado para schedule ${schedule.id} (${schedule.name})',
    );

    if (backupHistory != null) {
      final finishedAt = DateTime.now();
      final canceledHistory = backupHistory.copyWith(
        status: BackupStatus.warning,
        errorMessage: message,
        finishedAt: finishedAt,
        durationSeconds: finishedAt
            .difference(backupHistory.startedAt)
            .inSeconds,
      );
      final updateResult = await _backupHistoryRepository
          .updateHistoryAndLogIfRunning(
            history: canceledHistory,
            logStep: LogStepConstants.backupCancelled,
            logLevel: LogLevel.warning,
            logMessage: message,
          );
      updateResult.fold(
        (_) {},
        (e) => LoggerService.warning('Erro ao atualizar histórico e log: $e'),
      );
    }

    try {
      _progressNotifier.failBackup(message);
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao atualizar progresso failBackup', e, s);
    }

    return const rd.Failure(
      ValidationFailure(
        message: message,
        code: FailureCodes.backupCancelled,
      ),
    );
  }

  Future<List<BackupDestination>> _getDestinations(List<String> ids) async {
    if (ids.isEmpty) return [];
    final result = await _destinationRepository.getByIds(ids);
    return result.fold(
      (list) => list,
      (_) => <BackupDestination>[],
    );
  }

  /// Runs the scheduled backup immediately. Used both by local UI (Run now)
  /// and by remote client (ScheduleMessageHandler). Same flow in both cases;
  /// when triggered remotely, progress is streamed to the client via BackupProgressProvider.
  @override
  Future<rd.Result<void>> executeNow(String scheduleId) async {
    final result = await _scheduleRepository.getById(scheduleId);

    return result.fold(
      (schedule) async => _runScheduleWithLock(schedule),
      rd.Failure.new,
    );
  }

  @override
  Future<rd.Result<void>> cancelExecution(String scheduleId) async {
    if (scheduleId.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'ID do agendamento nao pode ser vazio',
          code: FailureCodes.validationFailed,
        ),
      );
    }

    if (!_executingSchedules.contains(scheduleId)) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Não há backup em execução para este schedule',
          code: FailureCodes.scheduleNotFound,
        ),
      );
    }

    _cancelRequestedSchedules.add(scheduleId);
    return const rd.Success(rd.unit);
  }

  @override
  Future<rd.Result<void>> refreshSchedule(String scheduleId) async {
    final result = await _scheduleRepository.getById(scheduleId);

    return result.fold((schedule) async {
      final nextRunAt = _scheduleCalculator.getNextRunTime(schedule);
      if (nextRunAt != null) {
        await _scheduleRepository.update(
          schedule.copyWith(nextRunAt: nextRunAt),
        );
      }
      return const rd.Success(rd.unit);
    }, rd.Failure.new);
  }

  @override
  bool get isRunning => _isRunning;

  Future<bool> _checkWritePermission(Directory directory) async {
    try {
      final testFileName =
          '.backup_permission_test_${DateTime.now().millisecondsSinceEpoch}';
      final testFile = File(
        '${directory.path}${Platform.pathSeparator}$testFileName',
      );

      await testFile.writeAsString('test');

      if (await testFile.exists()) {
        await testFile.delete();
        return true;
      }

      return false;
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao verificar permissão de escrita na pasta ${directory.path}: $e',
      );
      return false;
    }
  }

  Future<rd.Result<void>> _checkFreeSpace(
    Directory directory,
    Schedule schedule,
  ) async {
    final result = await _storageChecker.checkSpace(directory.path);

    return result.fold(
      (spaceInfo) {
        if (!spaceInfo.hasEnoughSpace(
          BackupConstants.minFreeSpaceForBackupBytes,
        )) {
          final errorMessage =
              'Espaço livre insuficiente na pasta de backup. '
              'Disponível: ${_formatBytes(spaceInfo.freeBytes)}, '
              'Mínimo necessário: '
              '${_formatBytes(BackupConstants.minFreeSpaceForBackupBytes)}';
          LoggerService.error(errorMessage);
          return rd.Failure(ValidationFailure(message: errorMessage));
        }

        LoggerService.info(
          'Verificação de espaço livre concluída: '
          '${_formatBytes(spaceInfo.freeBytes)} livres',
        );
        return const rd.Success(rd.unit);
      },
      rd.Failure.new,
    );
  }

  BackupMetrics? _mergeUploadAndCleanupMetrics(
    BackupMetrics? base,
    Duration uploadDuration,
    Duration cleanupDuration,
  ) {
    if (base == null) return null;
    return base.copyWith(
      uploadDuration: uploadDuration,
      cleanupDuration: cleanupDuration,
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// Aguarda todos os backups em execução terminarem.
  ///
  /// Útil para graceful shutdown - garante que backups em andamento
  /// tenham chance de completar antes do serviço encerrar.
  ///
  /// [timeout] Tempo máximo para aguardar (padrão: 5 minutos).
  /// Retorna `true` se todos os backups terminaram, `false` se timeout.
  @override
  Future<bool> waitForRunningBackups({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (_executingSchedules.isEmpty) {
      LoggerService.info('✅ Nenhum backup em execução');
      return true;
    }

    LoggerService.info(
      '⏳ Aguardando ${_executingSchedules.length} backup(s) em execução '
      '(timeout: ${timeout.inSeconds}s)',
    );
    LoggerService.info(
      'Schedules em execução: ${_executingSchedules.join(', ')}',
    );

    final startTime = DateTime.now();
    const checkInterval = Duration(seconds: 2);

    while (_executingSchedules.isNotEmpty) {
      final elapsed = DateTime.now().difference(startTime);

      if (elapsed >= timeout) {
        final remaining = _executingSchedules.toList();
        LoggerService.warning(
          '⚠️ Timeout atingido aguardando backups. '
          '${remaining.length} schedule(s) ainda em execução: ${remaining.join(', ')}',
        );
        return false;
      }

      // Loga progresso a cada 10 segundos
      if (elapsed.inSeconds % 10 == 0 && elapsed.inSeconds > 0) {
        LoggerService.info(
          '⏳ Aguardando... ${_executingSchedules.length} restante '
          '(${elapsed.inSeconds}s / ${timeout.inSeconds}s)',
        );
      }

      await Future.delayed(checkInterval);
    }

    final totalElapsed = DateTime.now().difference(startTime);
    LoggerService.info(
      '✅ Todos os backups concluídos em ${totalElapsed.inSeconds}s',
    );
    return true;
  }
}
