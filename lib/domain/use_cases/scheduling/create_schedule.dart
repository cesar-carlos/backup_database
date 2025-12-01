import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../entities/schedule.dart';
import '../../repositories/repositories.dart';
import '../../../infrastructure/external/scheduler/cron_parser.dart';
import '../../../application/services/scheduler_service.dart';

class CreateSchedule {
  final IScheduleRepository _repository;
  final SchedulerService _schedulerService;
  final ScheduleCalculator _calculator = ScheduleCalculator();

  CreateSchedule(this._repository, this._schedulerService);

  Future<rd.Result<Schedule>> call(Schedule schedule) async {
    // Validações
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

    // Calcular próxima execução
    final nextRunAt = _calculator.getNextRunTime(schedule);

    // Criar schedule com próxima execução calculada
    final scheduleWithNextRun = schedule.copyWith(
      nextRunAt: nextRunAt,
    );

    final result = await _repository.create(scheduleWithNextRun);

    // Se criado com sucesso, atualizar o serviço de agendamento
    result.fold(
      (createdSchedule) async {
        await _schedulerService.refreshSchedule(createdSchedule.id);
      },
      (failure) => null,
    );

    return result;
  }
}

