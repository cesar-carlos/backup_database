import 'package:backup_database/core/utils/error_mapper.dart' show mapExceptionToMessage;
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:flutter/foundation.dart';

class RemoteSchedulesProvider extends ChangeNotifier {
  RemoteSchedulesProvider(this._connectionManager);

  final ConnectionManager _connectionManager;

  List<Schedule> _schedules = [];
  bool _isLoading = false;
  bool _isUpdating = false;
  bool _isExecuting = false;
  String? _error;
  String? _updatingScheduleId;
  String? _executingScheduleId;

  String? _backupStep;
  String? _backupMessage;
  double? _backupProgress;

  List<Schedule> get schedules => _schedules;
  bool get isLoading => _isLoading;
  bool get isUpdating => _isUpdating;
  bool get isExecuting => _isExecuting;
  String? get error => _error;
  bool get isConnected => _connectionManager.isConnected;
  String? get updatingScheduleId => _updatingScheduleId;
  String? get executingScheduleId => _executingScheduleId;
  String? get backupStep => _backupStep;
  String? get backupMessage => _backupMessage;
  double? get backupProgress => _backupProgress;

  Future<void> loadSchedules() async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para ver os agendamentos.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _connectionManager.listSchedules();

    result.fold(
      (list) {
        _schedules = list;
        _isLoading = false;
      },
      (exception) {
        _error = mapExceptionToMessage(exception);
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<bool> updateSchedule(Schedule schedule) async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para atualizar agendamentos.';
      notifyListeners();
      return false;
    }

    _isUpdating = true;
    _updatingScheduleId = schedule.id;
    _error = null;
    notifyListeners();

    final result = await _connectionManager.updateSchedule(schedule);

    return result.fold(
      (updated) {
        final index = _schedules.indexWhere((s) => s.id == updated.id);
        if (index >= 0) {
          _schedules = List<Schedule>.from(_schedules)..[index] = updated;
        }
        _error = null;
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        return true;
      },
      (exception) {
        _error = mapExceptionToMessage(exception);
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> executeSchedule(String scheduleId) async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para executar agendamentos.';
      notifyListeners();
      return false;
    }

    _isExecuting = true;
    _executingScheduleId = scheduleId;
    _error = null;
    _backupStep = null;
    _backupMessage = null;
    _backupProgress = null;
    notifyListeners();

    final result = await _connectionManager.executeSchedule(
      scheduleId,
      onProgress: (step, message, progress) {
        _backupStep = step;
        _backupMessage = message;
        _backupProgress = progress;
        notifyListeners();
      },
    );

    return result.fold(
      (_) {
        _error = null;
        _isExecuting = false;
        _executingScheduleId = null;
        _backupStep = null;
        _backupMessage = null;
        _backupProgress = null;
        notifyListeners();
        return true;
      },
      (exception) {
        _error = mapExceptionToMessage(exception);
        _isExecuting = false;
        _executingScheduleId = null;
        _backupStep = null;
        _backupMessage = null;
        _backupProgress = null;
        notifyListeners();
        return false;
      },
    );
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  static const String _connectionLostMessage =
      'Conexão perdida; o backup pode ter continuado no servidor.';

  void clearExecutionStateOnDisconnect() {
    if (_executingScheduleId == null) return;
    _isExecuting = false;
    _executingScheduleId = null;
    _backupStep = null;
    _backupMessage = null;
    _backupProgress = null;
    _error = _connectionLostMessage;
    notifyListeners();
  }
}
