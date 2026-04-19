import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:backup_database/application/services/backup_orchestrator_service.dart';
import 'package:backup_database/core/constants/backup_constants.dart';
import 'package:backup_database/core/constants/log_step_constants.dart';
import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/logging/log_context.dart';
import 'package:backup_database/core/utils/directory_permission_check.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType, Schedule;
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/i_backup_cancellation_service.dart';
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
    IBackupCancellationService? cancellationService,
    Duration uploadTimeout = const Duration(hours: 4),
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
       _metricsCollector = metricsCollector,
       _cancellationService = cancellationService,
       _uploadTimeout = uploadTimeout;

  final IScheduleRepository _scheduleRepository;
  final IBackupDestinationRepository _destinationRepository;
  final IBackupHistoryRepository _backupHistoryRepository;
  final BackupOrchestratorService _backupOrchestratorService;
  final IDestinationOrchestrator _destinationOrchestrator;
  final IBackupCleanupService _cleanupService;
  final INotificationService _notificationService;
  final IScheduleCalculator _scheduleCalculator;
  // Mantido como dependência opcional do construtor para compatibilidade
  // com testes/wiring existente, embora o uso interno tenha sido movido
  // para `BackupOrchestratorService._estimateRequiredSpaceBytes`.
  // ignore: unused_field
  final IStorageChecker _storageChecker;
  final IBackupProgressNotifier _progressNotifier;
  final ILicensePolicyService _licensePolicyService;
  final ITransferStagingService? _transferStagingService;
  final IMetricsCollector? _metricsCollector;

  /// Opcional para preservar compatibilidade com testes que constroem o
  /// scheduler sem o serviço de cancelamento. Em produção é injetado via
  /// DI e usado para matar processos do SGBD imediatamente quando o
  /// usuário pede para cancelar (antes a flag só interrompia no próximo
  /// checkpoint).
  final IBackupCancellationService? _cancellationService;

  /// Timeout aplicado a todo o ciclo de upload para evitar que destinos
  /// travados (FTP lento, Drive offline) bloqueiem o backup
  /// indefinidamente. Configurável via construtor.
  final Duration _uploadTimeout;

  Timer? _checkTimer;
  bool _isRunning = false;
  final Set<String> _executingSchedules = {};
  final Set<String> _cancelRequestedSchedules = {};

  /// Mapeia `scheduleId` em execução para o `historyId` correspondente.
  /// Usado por `cancelExecution` para invocar
  /// `IBackupCancellationService.cancelByHistoryId` e matar o processo do
  /// SGBD imediatamente em vez de esperar o próximo checkpoint.
  final Map<String, String> _runningHistoryIds = {};

  @override
  bool get isExecutingBackup => _executingSchedules.isNotEmpty;

  @override
  Future<void> start() async {
    if (_isRunning) return;

    LoggerService.info('Iniciando serviço de agendamento');
    _isRunning = true;

    await _updateAllNextRuns();
    await _reconcileStaleRunningBackups();

    // Jitter inicial (0-30s) antes do primeiro tick para evitar que
    // todos os servidores em um cluster batam o banco no mesmo segundo.
    // Sem o jitter, vários SchedulerService.start() simultâneos (ex.: ao
    // reiniciar uma frota de máquinas) consultariam `getEnabledDueForExecution`
    // todos no segundo zero, causando picos de I/O previsíveis.
    final jitterSeconds = Random().nextInt(30);
    Timer(Duration(seconds: jitterSeconds), () {
      if (!_isRunning) return;
      _checkSchedules();
      _checkTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _checkSchedules(),
      );
    });

    LoggerService.info(
      'Serviço de agendamento iniciado (jitter inicial: ${jitterSeconds}s)',
    );
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

    // Bug histórico: usar `result.fold((schedules) async { ... })` aqui não
    // aguardava o callback assíncrono — `start()` retornava enquanto os
    // updates aconteciam em background. Usamos `getOrNull/exceptionOrNull`
    // para ficar com `await` de fato no fluxo principal.
    if (result.isError()) {
      final exception = result.exceptionOrNull();
      LoggerService.error(
        'Erro ao atualizar schedules: ${_failureMessage(exception)}',
      );
      return;
    }

    final schedules = result.getOrThrow();
    for (final schedule in schedules) {
      final nextRunAt = _scheduleCalculator.getNextRunTime(schedule);
      if (nextRunAt == null) continue;
      LoggerService.info(
        'Atualizando schedule ${schedule.name}: '
        'nextRunAt atual = ${schedule.nextRunAt}, '
        'novo nextRunAt = $nextRunAt',
      );
      await _scheduleRepository.update(
        schedule.copyWith(nextRunAt: nextRunAt),
      );
    }
    LoggerService.info('${schedules.length} schedules atualizados');
  }

  /// Helper centralizado para extrair mensagem amigável de um failure
  /// retornado por `result_dart`. Antes era reimplementado inline com
  /// `failure as Failure` (cast direto, crashava com tipos inesperados).
  String _failureMessage(Object? failure) {
    if (failure == null) return 'Erro desconhecido';
    if (failure is Failure) return failure.message;
    return failure.toString();
  }

  Future<void> _checkSchedules() async {
    if (!_isRunning) return;
    if (_executingSchedules.isNotEmpty) return;

    final now = DateTime.now();
    final result = await _scheduleRepository.getEnabledDueForExecution(now);

    result.fold(
      (schedules) {
        if (schedules.isEmpty) return;
        // Política: executa SOMENTE o primeiro vencido por tick. O lock
        // global em `_executeScheduledBackup` garante que não há dois
        // backups simultâneos. Os agendamentos restantes serão pegos no
        // próximo tick (1 minuto). Isso evita pico de I/O quando vários
        // schedules vencem ao mesmo tempo.
        final schedule = schedules.first;
        unawaited(_runDueScheduleFromTimer(schedule));
      },
      (failure) {
        LoggerService.error(
          'Falha ao buscar agendamentos vencidos para execução: $failure',
        );
      },
    );
  }

  Future<void> _runDueScheduleFromTimer(Schedule schedule) async {
    final result = await _runScheduleWithLock(schedule);
    if (result.isError()) {
      await _tryAdvanceScheduleNextRunOnFailure(schedule);
    }
  }

  Future<void> _tryAdvanceScheduleNextRunOnFailure(Schedule schedule) async {
    try {
      final nextRunAt = _scheduleCalculator.getNextRunTime(schedule);
      if (nextRunAt != null) {
        await _scheduleRepository.update(
          schedule.copyWith(nextRunAt: nextRunAt),
        );
        LoggerService.info(
          'Próxima execução de ${schedule.name} reagendada após falha '
          '(timer): $nextRunAt',
        );
      }
    } on Object catch (e, st) {
      LoggerService.warning(
        'Falha ao reagendar nextRunAt após backup com erro (timer)',
        e,
        st,
      );
    }
  }

  Future<void> _reconcileStaleRunningBackups() async {
    final result = await _backupHistoryRepository.reconcileStaleRunning(
      maxAge: BackupConstants.staleRunningBackupMaxAge,
    );
    result.fold(
      (count) {
        if (count > 0) {
          LoggerService.warning(
            'Reconciliados $count histórico(s) em execução órfãos '
            '(possível encerramento abrupto anterior).',
          );
        }
      },
      (failure) {
        LoggerService.warning(
          'Não foi possível reconciliar históricos running antigos: $failure',
        );
      },
    );
  }

  Future<rd.Result<void>> _executeScheduledBackup(Schedule schedule) async {
    LoggerService.info(
      'Executando backup agendado: ${schedule.name} '
      '(nextRunAt: ${schedule.nextRunAt}, now: ${DateTime.now()})',
    );

    String? tempBackupPath;
    final runId = '${schedule.id}_${const Uuid().v4()}';

    try {
      _licensePolicyService.setRunContext(runId);
      LogContext.setContext(runId: runId, scheduleId: schedule.id);

      // Garante que o BackupProgressProvider está em estado "running" para
      // que `setCurrentHistoryId` (chamado pelo orchestrator) consiga
      // publicar o historyId. Sem isso, o botão Cancelar do
      // BackupProgressDialog ficaria permanentemente desabilitado quando
      // o backup foi iniciado pela UI local. Retorno `false` é benigno —
      // significa que outro caller (ex.: socket handler) já reservou o
      // slot, o que é o comportamento desejado.
      _progressNotifier.tryStartBackup(schedule.name);
      _progressNotifier.setCurrentBackupName(schedule.name);

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

      // A validação de espaço livre vive agora dentro do
      // BackupOrchestratorService._estimateRequiredSpaceBytes (usa
      // tamanho real do banco × safetyFactor). Antes existia uma
      // checagem duplicada aqui com mínimo fixo de 500 MB que dava
      // false-positive em bancos grandes (passava no scheduler e
      // falhava no orchestrator).

      final outputDirectory = backupDir.path;
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
        LoggerService.error(
          'Execução bloqueada por licença: ${_failureMessage(failure)}',
          failure,
        );
        return rd.Failure(failure);
      }

      final backupResult = await _backupOrchestratorService.executeBackup(
        schedule: schedule,
        outputDirectory: outputDirectory,
      );

      if (backupResult.isError()) {
        final error = backupResult.exceptionOrNull()!;
        _safeFailBackup(_failureMessage(error));
        return rd.Failure(error);
      }

      final backupHistory = backupResult.getOrNull()!;
      tempBackupPath = backupHistory.backupPath;
      // Registra o mapeamento scheduleId → historyId para que
      // `cancelExecution` consiga matar o processo do SGBD imediatamente
      // via `IBackupCancellationService.cancelByHistoryId`.
      _runningHistoryIds[schedule.id] = backupHistory.id;

      final canceledAfterBackup = await _failIfCancellationRequested(
        schedule: schedule,
        backupHistory: backupHistory,
      );
      if (canceledAfterBackup != null) {
        return canceledAfterBackup;
      }

      final missingArtifactResultBefore = await _failIfArtifactMissing(
        backupHistory,
      );
      if (missingArtifactResultBefore != null) {
        return missingArtifactResultBefore;
      }

      final hasDestinations = destinations.isNotEmpty;

      if (hasDestinations) {
        final artifactType = await FileSystemEntity.type(
          backupHistory.backupPath,
        );
        if (artifactType == FileSystemEntityType.directory) {
          const errorMessage =
              'O backup resultou em uma pasta; os destinos configurados '
              'esperam um arquivo único. Ative compactação no agendamento ou '
              'remova os destinos até haver suporte a envio de pastas.';
          LoggerService.error(errorMessage);
          return _failScheduledBackupAfterArtifactError(
            backupHistory: backupHistory,
            errorMessage: errorMessage,
            logStep: LogStepConstants.backupDirectoryUploadNotSupported,
            failure: const ValidationFailure(message: errorMessage),
          );
        }
      }

      if (hasDestinations) {
        _safeUpdateProgress(
          step: 'Enviando para destino',
          message: 'Enviando para destinos...',
          progress: 0.85,
        );
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

      final missingArtifactResultBeforeUpload = await _failIfArtifactMissing(
        backupHistory,
      );
      if (missingArtifactResultBeforeUpload != null) {
        return missingArtifactResultBeforeUpload;
      }

      final uploadStopwatch = Stopwatch()..start();
      final backupIdForPath = schedule.databaseType == DatabaseType.sybase
          ? backupHistory.id
          : null;
      // Aplica timeout global ao ciclo de upload para evitar que destinos
      // travados (FTP lento, Drive offline) mantenham o backup pendurado
      // indefinidamente. Em timeout, simulamos failures para todas as
      // destinations não confirmadas e seguimos o fluxo de erro.
      List<rd.Result<void>> sendResults;
      try {
        sendResults = await _destinationOrchestrator
            .uploadToAllDestinations(
              sourceFilePath: backupHistory.backupPath,
              destinations: destinations,
              isCancelled: () =>
                  _cancelRequestedSchedules.contains(schedule.id),
              backupId: backupIdForPath,
              onProgress: _createThrottledUploadProgressCallback(
                destinations.length,
              ),
            )
            .timeout(_uploadTimeout);
      } on TimeoutException {
        LoggerService.error(
          'Upload para destinos excedeu o timeout de '
          '${_uploadTimeout.inMinutes} minutos para ${schedule.name}',
        );
        sendResults = List.generate(
          destinations.length,
          (_) => rd.Failure(
            BackupFailure(
              message:
                  'Upload excedeu timeout de ${_uploadTimeout.inMinutes} '
                  'minutos. Verifique conectividade ou aumente '
                  'uploadTimeout no scheduler.',
              code: FailureCodes.uploadFailed,
            ),
          ),
        );
      }
      uploadStopwatch.stop();
      final uploadDuration = uploadStopwatch.elapsed;
      _metricsCollector?.recordHistogram(
        ObservabilityMetrics.destinationUploadDurationMs,
        uploadDuration.inMilliseconds.toDouble(),
      );

      _safeUpdateProgress(
        step: 'Enviando para destino',
        message: 'Upload para destinos concluído.',
        progress: 0.95,
      );

      for (var index = 0; index < sendResults.length; index++) {
        final destination = destinations[index];
        final sendResult = sendResults[index];
        sendResult.fold((_) {}, (failure) {
          _metricsCollector?.incrementCounter(
            ObservabilityMetrics.destinationUploadFailureTotal,
          );
          final errorMessage =
              'Falha ao enviar para ${destination.name}: '
              '${_failureMessage(failure)}';
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

        _safeFailBackup(errorMessage);
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

      // Apaga o arquivo/diretório temporário SOMENTE quando o backup
      // terminou com sucesso (chegamos aqui sem ter retornado por
      // upload-error). Antes, o cleanup acontecia incondicionalmente,
      // o que resultava em perda de dados quando o upload falhava: o
      // único exemplar do backup era apagado da pasta local.
      await _deleteTempBackupArtifact(tempBackupPath);

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

        // Estes logs eram nível `info` antes, poluindo a saída de
        // produção com diagnóstico de uma issue específica de
        // backupPath vazio. Reduzimos para `debug` mantendo o conteúdo.
        LoggerService.debug('===== COMPLETANDO BACKUP =====');
        LoggerService.debug('stagingRelativePath: $stagingRelativePath');
        LoggerService.debug(
          'backupHistory.backupPath: ${backupHistory.backupPath}',
        );
        LoggerService.debug('pathToSend: $pathToSend');

        if (stagingRelativePath == null) {
          LoggerService.warning(
            'stagingRelativePath é null, usando backupPath original: '
            '$pathToSend',
          );
        }

        _progressNotifier.completeBackup(
          message: 'Backup concluído com sucesso!',
          backupPath: pathToSend,
        );

        LoggerService.debug(
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
      // Mensagem agora inclui qual schedule está bloqueando, facilitando
      // o diagnóstico — antes era genérica "já existe um backup em
      // execução".
      final running = _executingSchedules.join(', ');
      return rd.Failure(
        ValidationFailure(
          message:
              'Já existe um backup em execução no servidor '
              '(schedule(s): $running). Aguarde a conclusão para iniciar '
              'um novo.',
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
      _runningHistoryIds.remove(schedule.id);
    }
  }

  /// Apaga o arquivo ou diretório temporário do backup. Operação
  /// best-effort: erros são logados mas não interrompem o fluxo. Antes
  /// vivia inline no `_executeScheduledBackup`; extrair facilita reuso
  /// caso outros caminhos precisem fazer cleanup.
  Future<void> _deleteTempBackupArtifact(String path) async {
    try {
      final entityType = FileSystemEntity.typeSync(path);
      switch (entityType) {
        case FileSystemEntityType.file:
          final tempFile = File(path);
          if (tempFile.existsSync()) {
            await tempFile.delete();
            LoggerService.info('Arquivo temporário deletado: $path');
          }
        case FileSystemEntityType.directory:
          final tempDir = Directory(path);
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
            LoggerService.info('Diretório temporário deletado: $path');
          }
        default:
          LoggerService.debug(
            'Arquivo temporário não encontrado para exclusão: $path',
          );
      }
    } on Object catch (e) {
      LoggerService.warning('Erro ao deletar arquivo temporário: $e');
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

    _safeFailBackup(message);

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

    // Mata o processo do SGBD imediatamente em vez de esperar o próximo
    // checkpoint do `_failIfCancellationRequested`. Sem isso, um backup
    // travado em `pg_basebackup` ou `dbbackup` continuaria rodando até
    // terminar sozinho, ignorando o pedido de cancelamento.
    final historyId = _runningHistoryIds[scheduleId];
    final cancellationService = _cancellationService;
    if (historyId != null && cancellationService != null) {
      LoggerService.info(
        'Cancelando processo do backup historyId=$historyId '
        '(scheduleId=$scheduleId) via IBackupCancellationService',
      );
      cancellationService.cancelByHistoryId(historyId);
    } else {
      LoggerService.info(
        'Cancelamento marcado para scheduleId=$scheduleId. Processo '
        'do SGBD será interrompido no próximo checkpoint '
        '(historyId ou IBackupCancellationService indisponível).',
      );
    }

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

  /// Reporta falha ao progress notifier de forma resiliente. Centraliza o
  /// padrão `try { _progressNotifier.failBackup(msg); } catch ...` que
  /// antes era repetido em 4+ pontos do `_executeScheduledBackup`.
  void _safeFailBackup(String message) {
    try {
      _progressNotifier.failBackup(message);
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao atualizar progresso failBackup', e, s);
    }
  }

  /// Atualiza o progresso de forma resiliente (alguns updates são triviais
  /// e não devem interromper o backup se o notifier estiver com problema).
  void _safeUpdateProgress({
    required String step,
    required String message,
    double? progress,
  }) {
    try {
      _progressNotifier.updateProgress(
        step: step,
        message: message,
        progress: progress,
      );
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao atualizar progresso', e, s);
    }
  }

  Future<bool> _checkWritePermission(Directory directory) =>
      DirectoryPermissionCheck.hasWritePermission(directory);

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

  Future<bool> _pathExistsAsBackupArtifact(String path) async {
    final type = await FileSystemEntity.type(path);
    return type == FileSystemEntityType.file ||
        type == FileSystemEntityType.directory;
  }

  /// Verifica se o artefato do backup ainda existe em disco. Retorna `null`
  /// quando OK; um `Result<void>` de falha quando ausente. Antes este
  /// padrão era duplicado em dois pontos do `_executeScheduledBackup`
  /// com mesma mensagem e mesmo `_failScheduledBackupAfterArtifactError`.
  Future<rd.Result<void>?> _failIfArtifactMissing(
    BackupHistory backupHistory,
  ) async {
    if (await _pathExistsAsBackupArtifact(backupHistory.backupPath)) {
      return null;
    }
    final errorMessage =
        'Caminho do backup não encontrado (arquivo ou pasta): '
        '${backupHistory.backupPath}';
    LoggerService.error(errorMessage);
    return _failScheduledBackupAfterArtifactError(
      backupHistory: backupHistory,
      errorMessage: errorMessage,
      logStep: LogStepConstants.backupFileNotFound,
      failure: BackupFailure(message: errorMessage),
    );
  }

  Future<rd.Result<void>> _failScheduledBackupAfterArtifactError({
    required BackupHistory backupHistory,
    required String errorMessage,
    required String logStep,
    required Failure failure,
  }) async {
    final finishedAt = DateTime.now();
    final failedHistory = backupHistory.copyWith(
      status: BackupStatus.error,
      errorMessage: errorMessage,
      finishedAt: finishedAt,
      durationSeconds: finishedAt.difference(backupHistory.startedAt).inSeconds,
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
      (e) => LoggerService.warning('Erro ao atualizar histórico e log: $e'),
    );

    _safeFailBackup(errorMessage);
    return rd.Failure(failure);
  }

  static const _progressThrottleInterval = Duration(milliseconds: 250);
  static const _progressMinChangePercent = 2.0;

  void Function(double, [String?]) _createThrottledUploadProgressCallback(
    int totalDestinations,
  ) {
    DateTime? lastUpdateTime;
    var lastProgress = -1.0;

    void onProgress(double p, [String? stepOverride]) {
      try {
        final now = DateTime.now();
        final progress = 0.85 + p * 0.10;
        final pct = (p * 100).toInt();
        final shouldUpdate =
            lastUpdateTime == null ||
            p >= 0.99 ||
            p <= 0 ||
            now.difference(lastUpdateTime!) >= _progressThrottleInterval ||
            (p - lastProgress).abs() * 100 >= _progressMinChangePercent;

        if (!shouldUpdate) return;

        lastUpdateTime = now;
        lastProgress = p;

        var step = stepOverride ?? 'Enviando para destino';
        if (totalDestinations > 1) {
          step = 'Enviando para $totalDestinations destinos: $step';
        }
        final hasUploadPrefix =
            step.contains('Enviando') || step.contains('Retomando');
        final isComplete = p >= 0.99;
        final message = isComplete && hasUploadPrefix
            ? '$step concluído ✓'
            : hasUploadPrefix
            ? '$step — $pct%'
            : '$pct%';

        _progressNotifier.updateProgress(
          step: step,
          message: message,
          progress: progress,
        );
      } on Object catch (e, s) {
        LoggerService.debug('Erro ao atualizar progresso: $e', e, s);
      }
    }

    return onProgress;
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
    const progressLogInterval = Duration(seconds: 10);
    var lastProgressLog = startTime;

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

      // Bug histórico: usar `elapsed.inSeconds % 10 == 0` dependia de
      // que a checagem caísse exatamente no segundo 10/20/30, o que com
      // `checkInterval=2s` podia ser pulado (10 → próximo tick em 12s).
      // Agora rastreamos timestamp do último log e comparamos diferença.
      final now = DateTime.now();
      if (now.difference(lastProgressLog) >= progressLogInterval) {
        lastProgressLog = now;
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
