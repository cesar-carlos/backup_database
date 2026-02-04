import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/i_schedule_calculator.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class CreateSchedule {
  CreateSchedule(
    this._repository,
    this._schedulerService,
    this._calculator,
  );
  final IScheduleRepository _repository;
  final ISchedulerService _schedulerService;
  final IScheduleCalculator _calculator;

  Future<rd.Result<Schedule>> call(Schedule schedule) async {
    if (schedule.name.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Nome não pode ser vazio'),
      );
    }
    if (schedule.databaseConfigId.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Configuração de banco não selecionada'),
      );
    }
    if (schedule.destinationIds.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Pelo menos um destino deve ser selecionado',
        ),
      );
    }

    final nextRunAt = _calculator.getNextRunTime(schedule);
    final scheduleWithNextRun = schedule.copyWith(
      nextRunAt: nextRunAt,
    );

    final result = await _repository.create(scheduleWithNextRun);

    result.fold(
      (createdSchedule) async {
        await _schedulerService.refreshSchedule(createdSchedule.id);
      },
      (failure) => null,
    );

    return result;
  }
}
