import 'dart:async';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/domain/use_cases/scheduling/update_schedule.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';

typedef SendToClient = Future<void> Function(String clientId, Message message);

/// Handles remote schedule commands from the client. When the client sends
/// executeSchedule, the server runs the same backup flow as a local "Run now"
/// (ExecuteScheduledBackup → SchedulerService.executeNow → _executeScheduledBackup).
/// Progress (step, message, progress) is streamed to the client via
/// IBackupProgressNotifier so the client has the same information as the server UI.
class ScheduleMessageHandler {
  ScheduleMessageHandler({
    required IScheduleRepository scheduleRepository,
    required ISchedulerService schedulerService,
    required UpdateSchedule updateSchedule,
    required ExecuteScheduledBackup executeBackup,
    required IBackupProgressNotifier progressNotifier,
  }) : _scheduleRepository = scheduleRepository,
       _schedulerService = schedulerService,
       _updateSchedule = updateSchedule,
       _executeBackup = executeBackup,
       _progressNotifier = progressNotifier {
    _progressNotifier.addListener(_onProgressChanged);
  }

  final IScheduleRepository _scheduleRepository;
  final ISchedulerService _schedulerService;
  final UpdateSchedule _updateSchedule;
  final ExecuteScheduledBackup _executeBackup;
  final IBackupProgressNotifier _progressNotifier;

  String? _currentClientId;
  int? _currentRequestId;
  String? _currentScheduleId;
  SendToClient? _sendToClient;

  void dispose() {
    _progressNotifier.removeListener(_onProgressChanged);
  }

  Future<void> _onProgressChanged() async {
    if (_currentClientId == null ||
        _currentRequestId == null ||
        _currentScheduleId == null ||
        _sendToClient == null) {
      return;
    }

    final snapshot = _progressNotifier.currentSnapshot;
    if (snapshot == null) return;

    final progressValue = snapshot.progress ?? 0.0;

    // AGUARDAR o envio da primeira mensagem completar antes de continuar
    await _sendToClient!(
      _currentClientId!,
      createBackupProgressMessage(
        requestId: _currentRequestId!,
        scheduleId: _currentScheduleId!,
        step: snapshot.step,
        message: snapshot.message,
        progress: progressValue,
      ),
    );

    if (snapshot.step == 'Concluído') {
      // Log para rastrear backupPath
      LoggerService.info(
        '[ScheduleMessageHandler] ===== ENVIANDO backupComplete =====',
      );
      LoggerService.info(
        '[ScheduleMessageHandler] snapshot.backupPath: "${snapshot.backupPath}"',
      );
      LoggerService.info(
        '[ScheduleMessageHandler] snapshot.backupPath está vazio? ${snapshot.backupPath == null || snapshot.backupPath!.isEmpty}',
      );

      // AGUARDAR o envio da mensagem backupComplete completar
      await _sendToClient!(
        _currentClientId!,
        createBackupCompleteMessage(
          requestId: _currentRequestId!,
          scheduleId: _currentScheduleId!,
          message: snapshot.message,
          backupPath: snapshot.backupPath,
        ),
      );
      LoggerService.info(
        '[ScheduleMessageHandler] Mensagem backupComplete enviada',
      );
      _clearCurrentBackup();
    } else if (snapshot.step == 'Erro') {
      unawaited(
        _sendToClient!(
          _currentClientId!,
          createBackupFailedMessage(
            requestId: _currentRequestId!,
            scheduleId: _currentScheduleId!,
            error: snapshot.error ?? 'Erro desconhecido',
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

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    if (!isListSchedulesMessage(message) &&
        !isUpdateScheduleMessage(message) &&
        !isExecuteScheduleMessage(message) &&
        !isCancelScheduleMessage(message)) {
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
      } else if (isCancelScheduleMessage(message)) {
        await _handleCancelSchedule(
          clientId,
          requestId,
          message,
          sendToClient,
        );
      }
    } on Object catch (e, st) {
      LoggerService.warningWithContext(
        'ScheduleMessageHandler error',
        clientId: clientId,
        requestId: requestId.toString(),
        error: e,
        stackTrace: st,
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

    if (!_progressNotifier.tryStartBackup()) {
      LoggerService.infoWithContext(
        'Execute schedule rejected: backup already running',
        clientId: clientId,
        requestId: requestId.toString(),
        scheduleId: scheduleId,
      );
      await sendToClient(
        clientId,
        createScheduleErrorMessage(
          requestId: requestId,
          error:
              'Já existe um backup em execução no servidor. '
              'Aguarde conclusão para iniciar novo.',
        ),
      );
      return;
    }

    LoggerService.infoWithContext(
      'Execute schedule started',
      clientId: clientId,
      requestId: requestId.toString(),
      scheduleId: scheduleId,
    );

    try {
      final scheduleResult = await _scheduleRepository.getById(scheduleId);
      if (scheduleResult.isError()) {
        final failure = scheduleResult.exceptionOrNull();
        _progressNotifier.failBackup(
          failure?.toString() ?? 'Agendamento não encontrado',
        );
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
        _progressNotifier.failBackup('Agendamento não encontrado');
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

      _progressNotifier.setCurrentBackupName(schedule.name);
      _progressNotifier.updateProgress(
        step: 'Iniciando',
        message: 'Iniciando backup: ${schedule.name}',
        progress: 0,
      );
      _progressNotifier.updateProgress(
        step: 'Executando backup',
        message: 'Executando backup do banco de dados...',
        progress: 0.2,
      );

      final result = await _executeBackup(scheduleId);

      if (_currentClientId != null) {
        await result.fold(
          (_) async {
            LoggerService.infoWithContext(
              'Backup completed successfully',
              clientId: clientId,
              requestId: requestId.toString(),
              scheduleId: scheduleId,
            );
            final updatedScheduleResult = await _scheduleRepository.getById(
              scheduleId,
            );
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
            LoggerService.warningWithContext(
              'Backup failed',
              clientId: clientId,
              requestId: requestId.toString(),
              scheduleId: scheduleId,
              error: failure,
            );
            await sendToClient(
              clientId,
              createScheduleErrorMessage(
                requestId: requestId,
                error: errorMessage,
              ),
            );
            _progressNotifier.failBackup(errorMessage);
            _clearCurrentBackup();
          },
        );
      }
    } on Object catch (e, st) {
      LoggerService.warningWithContext(
        'Execute schedule error',
        clientId: clientId,
        requestId: requestId.toString(),
        scheduleId: scheduleId,
        error: e,
        stackTrace: st,
      );
      _progressNotifier.failBackup(e.toString());
      await sendToClient(
        clientId,
        createBackupFailedMessage(
          requestId: requestId,
          scheduleId: scheduleId,
          error: e.toString(),
        ),
      );
      _clearCurrentBackup();
    }
  }

  Future<void> _handleCancelSchedule(
    String clientId,
    int requestId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final scheduleId = getScheduleIdFromCancelRequest(message);
    if (scheduleId == null || scheduleId.isEmpty) {
      await sendToClient(
        clientId,
        createScheduleErrorMessage(
          requestId: requestId,
          error: 'scheduleId vazio ou inválido',
        ),
      );
      return;
    }

    // Só pode cancelar o backup do cliente atual
    if (scheduleId != _currentScheduleId) {
      await sendToClient(
        clientId,
        createScheduleErrorMessage(
          requestId: requestId,
          error: 'Não há backup em execução para este schedule',
        ),
      );
      return;
    }

    LoggerService.infoWithContext(
      'Cancel schedule requested',
      clientId: clientId,
      requestId: requestId.toString(),
      scheduleId: scheduleId,
    );

    final cancelResult = await _schedulerService.cancelExecution(scheduleId);
    if (cancelResult.isError()) {
      final failure = cancelResult.exceptionOrNull();
      await sendToClient(
        clientId,
        createScheduleErrorMessage(
          requestId: requestId,
          error: failure?.toString() ?? 'Falha ao cancelar backup',
        ),
      );
      return;
    }

    _clearCurrentBackup();

    await sendToClient(
      clientId,
      createScheduleCancelledMessage(
        requestId: requestId,
        scheduleId: scheduleId,
      ),
    );
  }
}
