import 'dart:async';

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/use_cases/scheduling/create_schedule.dart';
import 'package:backup_database/domain/use_cases/scheduling/delete_schedule.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/domain/use_cases/scheduling/update_schedule.dart';
import 'package:flutter/foundation.dart';

class SchedulerProvider extends ChangeNotifier with AsyncStateMixin {
  SchedulerProvider({
    required IScheduleRepository repository,
    required ISchedulerService schedulerService,
    required CreateSchedule createSchedule,
    required UpdateSchedule updateSchedule,
    required DeleteSchedule deleteSchedule,
    required ExecuteScheduledBackup executeBackup,
    BackupProgressProvider? progressProvider,
  }) : _repository = repository,
       _schedulerService = schedulerService,
       _createSchedule = createSchedule,
       _updateSchedule = updateSchedule,
       _deleteSchedule = deleteSchedule,
       _executeBackup = executeBackup,
       _progressProvider = progressProvider;
  final IScheduleRepository _repository;
  final ISchedulerService _schedulerService;
  final CreateSchedule _createSchedule;
  final UpdateSchedule _updateSchedule;
  final DeleteSchedule _deleteSchedule;
  final ExecuteScheduledBackup _executeBackup;
  final BackupProgressProvider? _progressProvider;

  List<Schedule> _schedules = [];
  bool _isSchedulerRunning = true;

  List<Schedule> get schedules => _schedules;
  bool get isSchedulerRunning => _isSchedulerRunning;

  List<Schedule> get activeSchedules =>
      _schedules.where((s) => s.enabled).toList();

  List<Schedule> get inactiveSchedules =>
      _schedules.where((s) => !s.enabled).toList();

  Future<void> loadSchedules() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao carregar agendamentos',
      action: () async {
        final result = await _repository.getAll();
        result.fold(
          (schedules) => _schedules = schedules,
          (failure) => throw failure,
        );
      },
    );
  }

  Future<bool> createSchedule(Schedule schedule) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao criar agendamento',
      action: () async {
        final result = await _createSchedule(schedule);
        result.fold(
          (_) {},
          (failure) => throw failure,
        );
        return true;
      },
    );
    if (ok ?? false) {
      await loadSchedules();
      return true;
    }
    return false;
  }

  Future<bool> updateSchedule(Schedule schedule) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao atualizar agendamento',
      action: () async {
        final result = await _updateSchedule(schedule);
        result.fold(
          (_) {},
          (failure) => throw failure,
        );
        return true;
      },
    );
    if (ok ?? false) {
      await loadSchedules();
      return true;
    }
    return false;
  }

  Future<bool> deleteSchedule(String id) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao deletar agendamento',
      action: () async {
        final result = await _deleteSchedule(id);
        result.fold(
          (_) {},
          (failure) => throw failure,
        );
        // P9: reassign em vez de mutação in-place para sinalizar mudança
        // a listeners que comparam com `identical()`.
        _schedules = _schedules.where((s) => s.id != id).toList();
        return true;
      },
    );
    return ok ?? false;
  }

  Future<bool> duplicateSchedule(Schedule source) async {
    final copy = Schedule(
      name: '${source.name} (cópia)',
      databaseConfigId: source.databaseConfigId,
      databaseType: source.databaseType,
      scheduleType: source.scheduleType,
      scheduleConfig: source.scheduleConfig,
      destinationIds: List<String>.from(source.destinationIds),
      backupFolder: source.backupFolder,
      backupType: source.backupType,
      truncateLog: source.truncateLog,
      compressBackup: source.compressBackup,
      compressionFormat: source.compressionFormat,
      enabled: source.enabled,
      enableChecksum: source.enableChecksum,
      verifyAfterBackup: source.verifyAfterBackup,
      postBackupScript: source.postBackupScript,
    );

    return createSchedule(copy);
  }

  Future<bool> executeNow(String scheduleId) async {
    final schedule = getScheduleById(scheduleId);
    final scheduleName = schedule?.name ?? 'Backup';
    final progressProvider = _progressProvider;

    // Reserva o slot de progresso com mutex (substitui o legado
    // `startBackup` que sobrescrevia o estado mesmo com backup concorrente).
    // Se um backup remoto / outro `executeNow` já estiver rodando, aborta
    // antes de invocar o orchestrator para evitar duas execuções
    // simultâneas com o mesmo notifier de progresso.
    var reservedProgressSlot = false;
    if (progressProvider != null) {
      reservedProgressSlot = progressProvider.tryStartBackup(scheduleName);
      if (!reservedProgressSlot) {
        setErrorManual(
          'Já existe um backup em execução. Aguarde a conclusão para '
          'iniciar outro.',
        );
        return false;
      }
      progressProvider.updateProgressWithStep(
        step: BackupStep.executingBackup,
        message: 'Executando backup do banco de dados...',
        progress: 0.2,
      );
    }

    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao executar backup',
      action: () async {
        final result = await _executeBackup(scheduleId);
        return result.fold(
          (_) {
            if (progressProvider != null) {
              progressProvider.completeBackup(
                message: 'Backup concluído com sucesso!',
              );
            }
            return true;
          },
          (failure) => throw failure,
        );
      },
    );

    if (!(ok ?? false) && progressProvider != null && reservedProgressSlot) {
      progressProvider.failBackup(error ?? 'Erro desconhecido');
    }
    return ok ?? false;
  }

  Future<bool> toggleSchedule(String id, bool enabled) async {
    final schedule = getScheduleById(id);
    if (schedule == null) {
      setErrorManual('Agendamento não encontrado.');
      return false;
    }
    return updateSchedule(schedule.copyWith(enabled: enabled));
  }

  void startScheduler() {
    unawaited(_schedulerService.start());
    _isSchedulerRunning = true;
    notifyListeners();
  }

  void stopScheduler() {
    _schedulerService.stop();
    _isSchedulerRunning = false;
    notifyListeners();
  }

  Schedule? getScheduleById(String id) {
    for (final s in _schedules) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Retorna agendamentos vinculados a um banco de dados.
  ///
  /// Retorna `null` apenas em **falha de leitura** (logada como warning).
  /// Lista vazia (`[]`) significa "nenhum schedule vinculado" e é
  /// distinguível do erro. Antes, ambos viravam `null` indistinguível.
  Future<List<Schedule>?> getSchedulesByDatabaseConfig(
    String databaseConfigId,
  ) async {
    try {
      final result = await _repository.getByDatabaseConfig(databaseConfigId);
      return result.fold(
        (schedules) => schedules,
        (failure) {
          LoggerService.warning(
            'Erro ao buscar schedules por database config '
            '($databaseConfigId): ${AsyncStateMixin.extractFailureMessage(failure)}',
          );
          return null;
        },
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        'Exceção inesperada ao buscar schedules por database config '
        '($databaseConfigId)',
        e,
        s,
      );
      return null;
    }
  }

  /// Retorna agendamentos vinculados a um destino de backup.
  /// Mesma semântica de erro/empty de [getSchedulesByDatabaseConfig].
  Future<List<Schedule>?> getSchedulesByDestination(
    String destinationId,
  ) async {
    try {
      final result = await _repository.getByDestinationId(destinationId);
      return result.fold(
        (schedules) => schedules,
        (failure) {
          LoggerService.warning(
            'Erro ao buscar schedules por destination ($destinationId): '
            '${AsyncStateMixin.extractFailureMessage(failure)}',
          );
          return null;
        },
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        'Exceção inesperada ao buscar schedules por destination '
        '($destinationId)',
        e,
        s,
      );
      return null;
    }
  }
}
