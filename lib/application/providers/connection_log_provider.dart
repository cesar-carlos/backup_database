import 'package:backup_database/domain/entities/connection_log.dart';
import 'package:backup_database/domain/repositories/i_connection_log_repository.dart';
import 'package:flutter/foundation.dart';

enum ConnectionLogFilter { all, success, failed }

const int _defaultRecentLimit = 100;

class ConnectionLogProvider extends ChangeNotifier {
  ConnectionLogProvider(this._repository);

  final IConnectionLogRepository _repository;

  List<ConnectionLog> _logs = [];
  bool _isLoading = false;
  String? _error;
  ConnectionLogFilter _filter = ConnectionLogFilter.all;

  List<ConnectionLog> get logs => _filteredLogs;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ConnectionLogFilter get filter => _filter;

  List<ConnectionLog> get _filteredLogs {
    switch (_filter) {
      case ConnectionLogFilter.all:
        return _logs;
      case ConnectionLogFilter.success:
        return _logs.where((l) => l.success).toList();
      case ConnectionLogFilter.failed:
        return _logs.where((l) => !l.success).toList();
    }
  }

  Future<void> loadLogs() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _repository.getRecentLogs(_defaultRecentLimit);

    result.fold(
      (list) {
        _logs = list;
        _isLoading = false;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  void setFilter(ConnectionLogFilter value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }
}
