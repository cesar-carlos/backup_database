import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/services/backup_orchestrator_service.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/i_backup_cleanup_service.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_destination_orchestrator.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:backup_database/domain/services/i_schedule_calculator.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_transfer_staging_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SchedulerService implements ISchedulerService {
  SchedulerService({
    required IScheduleRepository scheduleRepository,
    required IBackupDestinationRepository destinationRepository,
    required IBackupHistoryRepository backupHistoryRepository,
    required IBackupLogRepository backupLogRepository,
    required BackupOrchestratorService backupOrchestratorService,
    required IDestinationOrchestrator destinationOrchestrator,
    required IBackupCleanupService cleanupService,
    required INotificationService notificationService,
    required IScheduleCalculator scheduleCalculator,
    required IBackupProgressNotifier progressNotifier,
    ITransferStagingService? transferStagingService,
  }) : _scheduleRepository = scheduleRepository,
       _destinationRepository = destinationRepository,
       _backupHistoryRepository = backupHistoryRepository,
       _backupLogRepository = backupLogRepository,
       _backupOrchestratorService = backupOrchestratorService,
       _destinationOrchestrator = destinationOrchestrator,
       _cleanupService = cleanupService,
       _notificationService = notificationService,
       _scheduleCalculator = scheduleCalculator,
       _progressNotifier = progressNotifier,
       _transferStagingService = transferStagingService;

  final IScheduleRepository _scheduleRepository;
  final IBackupDestinationRepository _destinationRepository;
  final IBackupHistoryRepository _backupHistoryRepository;
  final IBackupLogRepository _backupLogRepository;
  final BackupOrchestratorService _backupOrchestratorService;
  final IDestinationOrchestrator _destinationOrchestrator;
  final IBackupCleanupService _cleanupService;
  final INotificationService _notificationService;
  final IScheduleCalculator _scheduleCalculator;
  final IBackupProgressNotifier _progressNotifier;
  final ITransferStagingService? _transferStagingService;

  Timer? _checkTimer;
  bool _isRunning = false;
  final Set<String> _executingSchedules = {};

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

    final result = await _scheduleRepository.getEnabled();

    result.fold((schedules) async {
      for (final schedule in schedules) {
        final isExecuting = _executingSchedules.contains(schedule.id);
        final shouldRun = _scheduleCalculator.shouldRunNow(schedule);

        if (isExecuting) {
          continue;
        }

        if (shouldRun) {
          _executingSchedules.add(schedule.id);

          final nextRunAt = _scheduleCalculator.getNextRunTime(schedule);
          if (nextRunAt != null) {
            await _scheduleRepository.update(
              schedule.copyWith(nextRunAt: nextRunAt),
            );
          }

          unawaited(
            _executeScheduledBackup(schedule)
                .then((_) {
                  _executingSchedules.remove(schedule.id);
                })
                .catchError((error) {
                  _executingSchedules.remove(schedule.id);
                }),
          );
        }
      }
    }, (failure) => null);
  }

  Future<rd.Result<void>> _executeScheduledBackup(Schedule schedule) async {
    LoggerService.info(
      'Executando backup agendado: ${schedule.name} '
      '(nextRunAt: ${schedule.nextRunAt}, now: ${DateTime.now()})',
    );

    late String tempBackupPath;
    var shouldDeleteTempFile = false;

    try {
      final destinations = await _getDestinations(schedule.destinationIds);

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
        await _backupHistoryRepository.update(failedHistory);

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

      final totalDestinations = destinations.length;

      for (var index = 0; index < destinations.length; index++) {
        final destination = destinations[index];

        if (!await backupFile.exists()) {
          final errorMessage =
              'Arquivo de backup foi deletado antes de enviar para '
              '${destination.name}: ${backupHistory.backupPath}';
          uploadErrors.add(errorMessage);
          LoggerService.error(errorMessage);
          hasCriticalUploadError = true;
          continue;
        }

        try {
          final progress = 0.85 + (0.1 * (index + 1) / totalDestinations);
          _progressNotifier.updateProgress(
            step: 'Enviando para destino',
            message: 'Enviando para ${destination.name}...',
            progress: progress,
          );
        } on Object catch (e, s) {
          LoggerService.warning('Erro ao atualizar progresso', e, s);
        }

        final sendResult = await _destinationOrchestrator.uploadToDestination(
          sourceFilePath: backupHistory.backupPath,
          destination: destination,
        );

        sendResult.fold((_) {}, (failure) {
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
        await _backupHistoryRepository.update(failedHistory);

        await _log(
          backupHistory.id,
          'error',
          'Falha ao enviar backup para destinos:\n$errorMessage',
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

      await _cleanupService.cleanOldBackups(
        destinations: destinations,
        backupHistoryId: backupHistory.id,
      );

      LoggerService.info('Backup agendado concluído: ${schedule.name}');

      if (_transferStagingService != null) {
        await _transferStagingService.copyToStaging(
          backupHistory.backupPath,
          schedule.id,
        );
      }

      try {
        _progressNotifier.updateProgress(
          step: 'Concluído',
          message: 'Backup concluído com sucesso!',
          progress: 1,
        );
      } on Object catch (e, s) {
        LoggerService.warning(
          'Erro ao atualizar progresso completeBackup',
          e,
          s,
        );
      }

      return const rd.Success(());
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro no backup agendado', e, stackTrace);
      return rd.Failure(
        BackupFailure(message: 'Erro no backup agendado: $e', originalError: e),
      );
    }
  }

  Future<List<BackupDestination>> _getDestinations(List<String> ids) async {
    final destinations = <BackupDestination>[];

    for (final id in ids) {
      final result = await _destinationRepository.getById(id);
      result.fold(
        destinations.add,
        (failure) => null,
      );
    }

    return destinations;
  }

  /// Runs the scheduled backup immediately. Used both by local UI (Run now)
  /// and by remote client (ScheduleMessageHandler). Same flow in both cases;
  /// when triggered remotely, progress is streamed to the client via BackupProgressProvider.
  @override
  Future<rd.Result<void>> executeNow(String scheduleId) async {
    final result = await _scheduleRepository.getById(scheduleId);

    return result.fold(
      (schedule) async => _executeScheduledBackup(schedule),
      rd.Failure.new,
    );
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
      return const rd.Success(());
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

  Future<void> _log(String historyId, String levelStr, String message) async {
    try {
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
    } on Object catch (e) {
      LoggerService.warning('Erro ao gravar log no banco: $e');
    }
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
