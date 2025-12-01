import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../entities/schedule.dart';
import '../../repositories/repositories.dart';
import '../../../infrastructure/external/scheduler/cron_parser.dart';
import '../../../application/services/scheduler_service.dart';

class UpdateSchedule {
  final IScheduleRepository _repository;
  final SchedulerService _schedulerService;
  final ScheduleCalculator _calculator = ScheduleCalculator();

  UpdateSchedule(this._repository, this._schedulerService);

  Future<rd.Result<Schedule>> call(Schedule schedule) async {
    // Validações
    if (schedule.id.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'ID não pode ser vazio'),
      );
    }
    if (schedule.name.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Nome não pode ser vazio'),
      );
    }

    // Recalcular próxima execução
    final nextRunAt = _calculator.getNextRunTime(schedule);

    final scheduleWithNextRun = schedule.copyWith(
      nextRunAt: nextRunAt,
    );

    final result = await _repository.update(scheduleWithNextRun);

    // Se atualizado com sucesso, atualizar o serviço de agendamento
    result.fold(
      (updatedSchedule) async {
        await _schedulerService.refreshSchedule(updatedSchedule.id);
      },
      (failure) => null,
    );

    return result;
  }
}

