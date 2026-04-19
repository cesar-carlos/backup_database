import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_schedule_calculator.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class CreateSchedule {
  CreateSchedule(
    this._repository,
    this._schedulerService,
    this._calculator,
    this._licensePolicyService,
    this._destinationRepository,
  );
  final IScheduleRepository _repository;
  final ISchedulerService _schedulerService;
  final IScheduleCalculator _calculator;
  final ILicensePolicyService _licensePolicyService;
  final IBackupDestinationRepository _destinationRepository;

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

    final destinationsResult = await _destinationRepository.getByIds(
      schedule.destinationIds,
    );
    if (destinationsResult.isError()) {
      return rd.Failure(destinationsResult.exceptionOrNull()!);
    }
    final destinations = destinationsResult.getOrNull()!;
    final policyResult = await _licensePolicyService
        .validateExecutionCapabilities(
          schedule,
          destinations,
        );
    if (policyResult.isError()) {
      return rd.Failure(policyResult.exceptionOrNull()!);
    }

    final nextRunAt = _calculator.getNextRunTime(schedule);
    final scheduleWithNextRun = schedule.copyWith(
      nextRunAt: nextRunAt,
    );

    final result = await _repository.create(scheduleWithNextRun);

    // Bug histórico: usar `result.fold((_) async { await refreshSchedule(); })`
    // não aguardava o callback async — `return result;` rodava imediatamente
    // e o caller recebia Success enquanto o scheduler ainda não havia sido
    // notificado. Em scheduler reactivo, isso significava que o próximo
    // tick podia rodar com a versão antiga do schedule.
    final createdSchedule = result.getOrNull();
    if (createdSchedule != null) {
      await _schedulerService.refreshSchedule(createdSchedule.id);
    }

    return result;
  }
}
