import 'dart:async';

import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/use_cases/scheduling/create_schedule.dart';
import 'package:backup_database/domain/use_cases/scheduling/delete_schedule.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/domain/use_cases/scheduling/update_schedule.dart';
import 'package:flutter/foundation.dart';

class SchedulerProvider extends ChangeNotifier {
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
  bool _isLoading = false;
  String? _error;
  bool _isSchedulerRunning = true;

  List<Schedule> get schedules => _schedules;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSchedulerRunning => _isSchedulerRunning;

  List<Schedule> get activeSchedules =>
      _schedules.where((s) => s.enabled).toList();

  List<Schedule> get inactiveSchedules =>
      _schedules.where((s) => !s.enabled).toList();

  Future<void> loadSchedules() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repository.getAll();
      result.fold(
        (schedules) {
          _schedules = schedules;
          _error = null;
        },
        (failure) {
          final f = failure as Failure;
          _error = f.message;
        },
      );
    } on Object catch (e) {
      _error = 'Erro ao carregar agendamentos: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createSchedule(Schedule schedule) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _createSchedule(schedule);
      return await result.fold(
        (newSchedule) async {
          await loadSchedules();
          return true;
        },
        (failure) async {
          final f = failure as Failure;
          _error = f.message;
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );
    } on Object catch (e) {
      _error = 'Erro ao criar agendamento: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateSchedule(Schedule schedule) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _updateSchedule(schedule);
      return await result.fold(
        (updatedSchedule) async {
          await loadSchedules();
          return true;
        },
        (failure) async {
          final f = failure as Failure;
          _error = f.message;
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );
    } on Object catch (e) {
      _error = 'Erro ao atualizar agendamento: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteSchedule(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _deleteSchedule(id);
      return result.fold(
        (_) {
          _schedules.removeWhere((s) => s.id == id);
          _error = null;
          _isLoading = false;
          notifyListeners();
          return true;
        },
        (failure) {
          final f = failure as Failure;
          _error = f.message;
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );
    } on Object catch (e) {
      _error = 'Erro ao deletar agendamento: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
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
    _isLoading = true;
    _error = null;
    notifyListeners();

    final schedule = getScheduleById(scheduleId);
    final scheduleName = schedule?.name ?? 'Backup';
    final progressProvider = _progressProvider;

    try {
      if (progressProvider != null) {
        progressProvider.startBackup(scheduleName);
        progressProvider.updateProgressWithStep(
          step: BackupStep.executingBackup,
          message: 'Executando backup do banco de dados...',
          progress: 0.2,
        );
      }

      final result = await _executeBackup(scheduleId);

      return result.fold(
        (_) {
          if (progressProvider != null) {
            progressProvider.updateProgressWithStep(
              step: BackupStep.completed,
              message: 'Backup concluído com sucesso!',
              progress: 1,
            );
            progressProvider.completeBackup(
              message: 'Backup concluído com sucesso!',
            );
          }
          _error = null;
          _isLoading = false;
          notifyListeners();
          return true;
        },
        (failure) {
          final f = failure as Failure;
          if (progressProvider != null) {
            progressProvider.failBackup(f.message);
          }
          _error = f.message;
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );
    } on Object catch (e) {
      if (progressProvider != null) {
        progressProvider.failBackup(e.toString());
      }
      _error = 'Erro ao executar backup: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleSchedule(String id, bool enabled) async {
    final schedule = _schedules.firstWhere((s) => s.id == id);
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
    try {
      return _schedules.firstWhere((s) => s.id == id);
    } on Object catch (e) {
      return null;
    }
  }

  Future<List<Schedule>?> getSchedulesByDatabaseConfig(
    String databaseConfigId,
  ) async {
    try {
      final result = await _repository.getByDatabaseConfig(databaseConfigId);
      return result.fold((schedules) => schedules, (failure) => null);
    } on Object {
      return null;
    }
  }

  Future<List<Schedule>?> getSchedulesByDestination(
    String destinationId,
  ) async {
    try {
      final result = await _repository.getByDestinationId(destinationId);
      return result.fold((schedules) => schedules, (failure) => null);
    } on Object {
      return null;
    }
  }
}
