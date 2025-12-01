import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../application/services/scheduler_service.dart';

class ExecuteScheduledBackup {
  final SchedulerService _schedulerService;

  ExecuteScheduledBackup(this._schedulerService);

  Future<rd.Result<void>> call(String scheduleId) async {
    if (scheduleId.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'ID do agendamento não pode ser vazio'),
      );
    }

    return await _schedulerService.executeNow(scheduleId);
  }
}

