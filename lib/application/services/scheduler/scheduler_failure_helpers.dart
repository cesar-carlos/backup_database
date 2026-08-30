import 'dart:io';

import 'package:backup_database/application/services/scheduler/scheduler_execution_lock.dart';
import 'package:backup_database/core/constants/log_step_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/schedule.dart' show Schedule;
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SchedulerFailureHelpers {
  SchedulerFailureHelpers({
    required this._backupHistoryRepository,
    required this._progressNotifier,
    required this._lock,
  });

  final IBackupHistoryRepository _backupHistoryRepository;
  final IBackupProgressNotifier _progressNotifier;
  final SchedulerExecutionLock _lock;

  void safeFailBackup(String message) {
    try {
      _progressNotifier.failBackup(message);
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao atualizar progresso failBackup', e, s);
    }
  }

  void safeCancelBackup(String reason) {
    try {
      _progressNotifier.cancelBackup(reason);
    } on Object catch (e, s) {
      LoggerService.warning(
        'Erro ao atualizar progresso cancelBackup',
        e,
        s,
      );
    }
  }

  void safeUpdateProgress({
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

  Future<rd.Result<void>?> failIfCancellationRequested({
    required Schedule schedule,
    BackupHistory? backupHistory,
  }) async {
    if (!_lock.cancelRequestedSchedules.contains(schedule.id)) {
      return null;
    }

    final watchdogReason = _lock.watchdogCancelReasonByScheduleId[schedule.id];
    final message = watchdogReason != null
        ? 'Backup cancelado por watchdog: $watchdogReason.'
        : 'Backup cancelado pelo usuario.';
    LoggerService.warning(
      'Cancelamento detectado para schedule ${schedule.id} '
      '(${schedule.name})'
      '${watchdogReason != null ? ' (reason=$watchdogReason)' : ''}',
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
        (e) => LoggerService.warning(
          'Erro ao atualizar histórico e log: $e',
        ),
      );
    }

    safeCancelBackup(message);

    return rd.Failure(
      ValidationFailure(
        message: message,
        code: FailureCodes.backupCancelled,
      ),
    );
  }

  Future<rd.Result<void>?> failIfArtifactMissing(
    BackupHistory backupHistory,
  ) async {
    if (await _pathExistsAsBackupArtifact(backupHistory.backupPath)) {
      return null;
    }
    final errorMessage =
        'Caminho do backup não encontrado (arquivo ou pasta): '
        '${backupHistory.backupPath}';
    LoggerService.error(errorMessage);
    return failScheduledBackupAfterArtifactError(
      backupHistory: backupHistory,
      errorMessage: errorMessage,
      logStep: LogStepConstants.backupFileNotFound,
      failure: BackupFailure(message: errorMessage),
    );
  }

  Future<rd.Result<void>> failScheduledBackupAfterArtifactError({
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

    safeFailBackup(errorMessage);
    return rd.Failure(failure);
  }

  Future<bool> _pathExistsAsBackupArtifact(String path) async {
    final type = await FileSystemEntity.type(path);
    return type == FileSystemEntityType.file ||
        type == FileSystemEntityType.directory;
  }
}
