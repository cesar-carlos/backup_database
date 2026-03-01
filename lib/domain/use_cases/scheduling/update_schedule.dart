import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/domain/services/i_schedule_calculator.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class UpdateSchedule {
  UpdateSchedule(
    this._repository,
    this._schedulerService,
    this._calculator,
    this._licensePolicyService,
    this._destinationRepository, {
    IMetricsCollector? metricsCollector,
  }) : _metricsCollector = metricsCollector;

  final IScheduleRepository _repository;
  final ISchedulerService _schedulerService;
  final IScheduleCalculator _calculator;
  final ILicensePolicyService _licensePolicyService;
  final IBackupDestinationRepository _destinationRepository;
  final IMetricsCollector? _metricsCollector;

  Future<rd.Result<Schedule>> call(Schedule schedule) async {
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

    if (schedule.destinationIds.isNotEmpty) {
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
        final failure = policyResult.exceptionOrNull()!;
        if (failure is Failure && failure.code == FailureCodes.licenseDenied) {
          _metricsCollector?.incrementCounter(
            ObservabilityMetrics.scheduleUpdateRejectedTotal,
          );
        }
        return rd.Failure(failure);
      }
    } else {
      final policyResult = await _licensePolicyService
          .validateScheduleCapabilities(schedule);
      if (policyResult.isError()) {
        final failure = policyResult.exceptionOrNull()!;
        if (failure is Failure && failure.code == FailureCodes.licenseDenied) {
          _metricsCollector?.incrementCounter(
            ObservabilityMetrics.scheduleUpdateRejectedTotal,
          );
        }
        return rd.Failure(failure);
      }
    }

    final nextRunAt = _calculator.getNextRunTime(schedule);

    final scheduleWithNextRun = schedule.copyWith(
      nextRunAt: nextRunAt,
    );

    final result = await _repository.update(scheduleWithNextRun);

    result.fold(
      (updatedSchedule) async {
        await _schedulerService.refreshSchedule(updatedSchedule.id);
      },
      (failure) => null,
    );

    return result;
  }
}
