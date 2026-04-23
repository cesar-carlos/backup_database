import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/execution_origin.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ExecuteScheduledBackup {
  ExecuteScheduledBackup(this._schedulerService);
  final ISchedulerService _schedulerService;

  Future<rd.Result<void>> call(
    String scheduleId, {
    ExecutionOrigin executionOrigin = ExecutionOrigin.local,
  }) async {
    if (scheduleId.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'ID do agendamento não pode ser vazio'),
      );
    }

    return _schedulerService.executeNow(
      scheduleId,
      executionOrigin: executionOrigin,
    );
  }
}
