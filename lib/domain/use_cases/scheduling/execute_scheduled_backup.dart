import 'package:backup_database/application/services/scheduler_service.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ExecuteScheduledBackup {
  ExecuteScheduledBackup(this._schedulerService);
  final SchedulerService _schedulerService;

  Future<rd.Result<void>> call(String scheduleId) async {
    if (scheduleId.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'ID do agendamento não pode ser vazio'),
      );
    }

    return _schedulerService.executeNow(scheduleId);
  }
}
