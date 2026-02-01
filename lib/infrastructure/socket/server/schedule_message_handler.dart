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
  })  : _scheduleRepository = scheduleRepository,
        _updateSchedule = updateSchedule,
        _executeBackup = executeBackup;

  final IScheduleRepository _scheduleRepository;
  final UpdateSchedule _updateSchedule;
  final ExecuteScheduledBackup _executeBackup;

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

    final result = await _executeBackup(scheduleId);
    await result.fold(
      (_) async {
        final scheduleResult = await _scheduleRepository.getById(scheduleId);
        scheduleResult.fold(
          (schedule) async {
            await sendToClient(
              clientId,
              createScheduleUpdatedMessage(
                requestId: requestId,
                schedule: schedule,
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
}
