import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:flutter/foundation.dart';

class RemoteSchedulesProvider extends ChangeNotifier {
  RemoteSchedulesProvider(this._connectionManager);

  final ConnectionManager _connectionManager;

  List<Schedule> _schedules = [];
  bool _isLoading = false;
  String? _error;

  List<Schedule> get schedules => _schedules;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _connectionManager.isConnected;

  Future<void> loadSchedules() async {
    if (!_connectionManager.isConnected) {
      _error = 'Não conectado ao servidor';
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
      (failure) {
        _error = failure.toString();
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<bool> updateSchedule(Schedule schedule) async {
    if (!_connectionManager.isConnected) {
      _error = 'Não conectado ao servidor';
      notifyListeners();
      return false;
    }

    final result = await _connectionManager.updateSchedule(schedule);
    return result.fold(
      (updated) {
        final index = _schedules.indexWhere((s) => s.id == updated.id);
        if (index >= 0) {
          _schedules = List<Schedule>.from(_schedules)..[index] = updated;
        }
        _error = null;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.toString();
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> executeSchedule(String scheduleId) async {
    if (!_connectionManager.isConnected) {
      _error = 'Não conectado ao servidor';
      notifyListeners();
      return false;
    }

    final result = await _connectionManager.executeSchedule(scheduleId);
    return result.fold(
      (_) {
        _error = null;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.toString();
        notifyListeners();
        return false;
      },
    );
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
