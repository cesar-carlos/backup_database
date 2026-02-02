import 'dart:async';

import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/domain/use_cases/scheduling/update_schedule.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';

typedef SendToClient = Future<void> Function(String clientId, Message message);

class ScheduleMessageHandler {
  ScheduleMessageHandler({
    required IScheduleRepository scheduleRepository,
    required UpdateSchedule updateSchedule,
    required ExecuteScheduledBackup executeBackup,
    required BackupProgressProvider progressProvider,
  })  : _scheduleRepository = scheduleRepository,
        _updateSchedule = updateSchedule,
        _executeBackup = executeBackup,
        _progressProvider = progressProvider {
    _progressProvider.addListener(_onProgressChanged);
  }

  final IScheduleRepository _scheduleRepository;
  final UpdateSchedule _updateSchedule;
  final ExecuteScheduledBackup _executeBackup;
  final BackupProgressProvider _progressProvider;

  String? _currentClientId;
  int? _currentRequestId;
  String? _currentScheduleId;
  SendToClient? _sendToClient;

  void dispose() {
    _progressProvider.removeListener(_onProgressChanged);
  }

  void _onProgressChanged() {
    if (_currentClientId == null ||
        _currentRequestId == null ||
        _currentScheduleId == null ||
        _sendToClient == null) {
      return;
    }

    final progress = _progressProvider.currentProgress;
    if (progress == null) return;

    final step = _stepToString(progress.step);
    final progressValue = progress.progress ?? 0.0;

    unawaited(
      _sendToClient!(
        _currentClientId!,
        createBackupProgressMessage(
          requestId: _currentRequestId!,
          scheduleId: _currentScheduleId!,
          step: step,
          message: progress.message,
          progress: progressValue,
        ),
      ),
    );

    if (progress.step == BackupStep.completed) {
      unawaited(
        _sendToClient!(
          _currentClientId!,
          createBackupCompleteMessage(
            requestId: _currentRequestId!,
            scheduleId: _currentScheduleId!,
            message: progress.message,
          ),
        ),
      );
      _clearCurrentBackup();
    } else if (progress.step == BackupStep.error) {
      unawaited(
        _sendToClient!(
          _currentClientId!,
          createBackupFailedMessage(
            requestId: _currentRequestId!,
            scheduleId: _currentScheduleId!,
            error: progress.error ?? 'Erro desconhecido',
          ),
        ),
      );
      _clearCurrentBackup();
    }
  }

  void _clearCurrentBackup() {
    _currentClientId = null;
    _currentRequestId = null;
    _currentScheduleId = null;
    _sendToClient = null;
  }

  String _stepToString(BackupStep step) {
    switch (step) {
      case BackupStep.initializing:
        return 'Iniciando';
      case BackupStep.executingBackup:
        return 'Executando backup';
      case BackupStep.compressing:
        return 'Compactando';
      case BackupStep.uploading:
        return 'Enviando para destino';
      case BackupStep.completed:
        return 'Concluído';
      case BackupStep.error:
        return 'Erro';
    }
  }

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    if (!isListSchedulesMessage(message) &&
        !isUpdateScheduleMessage(message) &&
        !isExecuteScheduleMessage(message)) {
      return;
    }

    final requestId = message.header.requestId;

    try {
      if (isListSchedulesMessage(message)) {
        await _handleListSchedules(clientId, requestId, sendToClient);
      } else if (isUpdateScheduleMessage(message)) {
        await _handleUpdateSchedule(
          clientId,
          requestId,
          message,
          sendToClient,
        );
      } else if (isExecuteScheduleMessage(message)) {
        await _handleExecuteSchedule(
          clientId,
          requestId,
          message,
          sendToClient,
        );
      }
    } on Object catch (e, st) {
      LoggerService.warning(
        'ScheduleMessageHandler error for client $clientId',
        e,
        st,
      );
      await sendToClient(
        clientId,
        createScheduleErrorMessage(requestId: requestId, error: e.toString()),
      );
    }
  }

  Future<void> _handleListSchedules(
    String clientId,
    int requestId,
    SendToClient sendToClient,
  ) async {
    final result = await _scheduleRepository.getAll();
    result.fold(
      (schedules) async {
        await sendToClient(
          clientId,
          createScheduleListMessage(
            requestId: requestId,
            schedules: schedules,
          ),
        );
      },
      (failure) async {
        await sendToClient(
          clientId,
          createScheduleErrorMessage(
            requestId: requestId,
            error: failure.toString(),
          ),
        );
      },
    );
  }

  Future<void> _handleUpdateSchedule(
    String clientId,
    int requestId,
    Message message,
    SendToClient sendToClient,
  ) async {
    try {
      final schedule = getScheduleFromUpdatePayload(message);
      final result = await _updateSchedule(schedule);
      result.fold(
        (updated) async {
          await sendToClient(
            clientId,
            createScheduleUpdatedMessage(
              requestId: requestId,
              schedule: updated,
            ),
          );
        },
        (failure) async {
          await sendToClient(
            clientId,
            createScheduleErrorMessage(
              requestId: requestId,
              error: failure.toString(),
            ),
          );
        },
      );
    } on Object catch (e) {
      await sendToClient(
        clientId,
        createScheduleErrorMessage(
          requestId: requestId,
          error: e.toString(),
        ),
      );
    }
  }

  Future<void> _handleExecuteSchedule(
    String clientId,
    int requestId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final scheduleId = getScheduleIdFromExecutePayload(message);
    if (scheduleId.isEmpty) {
      await sendToClient(
        clientId,
        createScheduleErrorMessage(
          requestId: requestId,
          error: 'scheduleId vazio',
        ),
      );
      return;
    }

    if (_progressProvider.isRunning) {
      await sendToClient(
        clientId,
        createScheduleErrorMessage(
          requestId: requestId,
          error: 'Já existe um backup em execução no servidor. '
              'Aguarde conclusão para iniciar novo.',
        ),
      );
      return;
    }

    final scheduleResult = await _scheduleRepository.getById(scheduleId);
    if (scheduleResult.isError()) {
      final failure = scheduleResult.exceptionOrNull();
      await sendToClient(
        clientId,
        createScheduleErrorMessage(
          requestId: requestId,
          error: failure?.toString() ?? 'Agendamento não encontrado',
        ),
      );
      return;
    }

    final schedule = scheduleResult.getOrNull();
    if (schedule == null) {
      await sendToClient(
        clientId,
        createScheduleErrorMessage(
          requestId: requestId,
          error: 'Agendamento não encontrado',
        ),
      );
      return;
    }

    _currentClientId = clientId;
    _currentRequestId = requestId;
    _currentScheduleId = scheduleId;
    _sendToClient = sendToClient;

    _progressProvider.startBackup(schedule.name);

    final result = await _executeBackup(scheduleId);

    if (_currentClientId != null) {
      await result.fold(
        (_) async {
          final updatedScheduleResult =
              await _scheduleRepository.getById(scheduleId);
          updatedScheduleResult.fold(
            (updatedSchedule) async {
              await sendToClient(
                clientId,
                createScheduleUpdatedMessage(
                  requestId: requestId,
                  schedule: updatedSchedule,
                ),
              );
            },
            (failure) async {
              await sendToClient(
                clientId,
                createScheduleErrorMessage(
                  requestId: requestId,
                  error: failure.toString(),
                ),
              );
            },
          );
        },
        (failure) async {
          final errorMessage = failure.toString();
          await sendToClient(
            clientId,
            createScheduleErrorMessage(
              requestId: requestId,
              error: errorMessage,
            ),
          );
        },
      );
    }
  }
}
