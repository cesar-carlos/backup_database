import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/domain/entities/connection_log.dart';
import 'package:backup_database/domain/repositories/i_connection_log_repository.dart';
import 'package:flutter/foundation.dart';

enum ConnectionLogFilter { all, success, failed }

const int _defaultRecentLimit = 100;

class ConnectionLogProvider extends ChangeNotifier with AsyncStateMixin {
  ConnectionLogProvider(this._repository);

  final IConnectionLogRepository _repository;

  List<ConnectionLog> _logs = [];
  ConnectionLogFilter _filter = ConnectionLogFilter.all;

  List<ConnectionLog> get logs => _filteredLogs;
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
    await runAsync<void>(
      action: () async {
        final result = await _repository.getRecentLogs(_defaultRecentLimit);
        result.fold(
          (list) => _logs = list,
          (failure) => throw failure,
        );
      },
    );
  }

  void setFilter(ConnectionLogFilter value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }
}
