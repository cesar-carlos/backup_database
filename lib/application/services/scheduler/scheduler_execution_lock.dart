import 'package:backup_database/core/constants/backup_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/domain/entities/execution_origin.dart';
import 'package:backup_database/domain/entities/schedule.dart' show Schedule;
import 'package:result_dart/result_dart.dart' as rd;

class SchedulerExecutionLock {
  final Set<String> executingSchedules = {};
  final Set<String> cancelRequestedSchedules = {};
  final Map<String, String> runningHistoryIds = {};
  final Map<String, DateTime> lastProgressAtByScheduleId = {};
  final Map<String, DateTime> startedAtByScheduleId = {};
  final Map<String, String> watchdogCancelReasonByScheduleId = {};

  bool get isExecutingBackup => executingSchedules.isNotEmpty;

  bool get hasAvailableSlot =>
      executingSchedules.length < BackupConstants.maxConcurrentBackups;

  Future<rd.Result<void>> run(
    Schedule schedule, {
    required Future<rd.Result<void>> Function(
      Schedule schedule, {
      ExecutionOrigin executionOrigin,
      String? runId,
    })
    execute,
    ExecutionOrigin executionOrigin = ExecutionOrigin.local,
    String? runId,
  }) async {
    if (!hasAvailableSlot) {
      final running = executingSchedules.join(', ');
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

    executingSchedules.add(schedule.id);
    final startedAt = DateTime.now();
    startedAtByScheduleId[schedule.id] = startedAt;
    lastProgressAtByScheduleId[schedule.id] = startedAt;
    try {
      return await execute(
        schedule,
        executionOrigin: executionOrigin,
        runId: runId,
      );
    } finally {
      executingSchedules.remove(schedule.id);
      cancelRequestedSchedules.remove(schedule.id);
      runningHistoryIds.remove(schedule.id);
      startedAtByScheduleId.remove(schedule.id);
      lastProgressAtByScheduleId.remove(schedule.id);
      watchdogCancelReasonByScheduleId.remove(schedule.id);
    }
  }
}
