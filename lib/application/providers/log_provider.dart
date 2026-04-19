import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/application/services/log_service.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:flutter/foundation.dart';

class LogProvider extends ChangeNotifier with AsyncStateMixin {
  LogProvider(this._logService);
  final LogService _logService;

  List<BackupLog> _logs = [];

  LogLevel? _filterLevel;
  LogCategory? _filterCategory;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String _searchQuery = '';

  int _currentPage = 0;
  final int _pageSize = 50;
  bool _hasMore = true;

  List<BackupLog> get logs => _logs;
  LogLevel? get filterLevel => _filterLevel;
  LogCategory? get filterCategory => _filterCategory;
  DateTime? get filterStartDate => _filterStartDate;
  DateTime? get filterEndDate => _filterEndDate;
  String get searchQuery => _searchQuery;
  bool get hasMore => _hasMore;
  int get currentPage => _currentPage;
  int get pageSize => _pageSize;

  Future<void> loadLogs({bool append = false}) async {
    // Evita recarregamento concorrente da mesma página.
    if (isLoading) return;

    await runAsync<void>(
      genericErrorMessage: 'Erro ao carregar logs',
      action: () async {
        final result = await _logService.getLogs(
          limit: _pageSize,
          offset: append ? _logs.length : 0,
          level: _filterLevel,
          category: _filterCategory,
          startDate: _filterStartDate,
          endDate: _filterEndDate,
          searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        );

        result.fold(
          (newLogs) {
            if (append) {
              _logs = [..._logs, ...newLogs];
            } else {
              _logs = newLogs;
              _currentPage = 0;
            }
            _hasMore = newLogs.length == _pageSize;
          },
          (failure) => throw failure,
        );
      },
    );
  }

  Future<void> loadMore() async {
    if (!_hasMore || isLoading) return;
    _currentPage++;
    await loadLogs(append: true);
  }

  Future<void> refresh() async {
    _currentPage = 0;
    _hasMore = true;
    await loadLogs();
  }

  void setFilterLevel(LogLevel? level) {
    _filterLevel = level;
    refresh();
  }

  void setFilterCategory(LogCategory? category) {
    _filterCategory = category;
    refresh();
  }

  void setFilterDateRange(DateTime? startDate, DateTime? endDate) {
    _filterStartDate = startDate;
    _filterEndDate = endDate;
    refresh();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    refresh();
  }

  void clearFilters() {
    _filterLevel = null;
    _filterCategory = null;
    _filterStartDate = null;
    _filterEndDate = null;
    _searchQuery = '';
    refresh();
  }

  Future<String?> exportLogs({
    required String outputPath,
    required ExportFormat format,
  }) {
    return runAsync<String>(
      genericErrorMessage: 'Erro ao exportar logs',
      action: () async {
        final result = await _logService.exportLogs(
          outputPath: outputPath,
          format: format,
          startDate: _filterStartDate,
          endDate: _filterEndDate,
        );
        return result.fold(
          (filePath) => filePath,
          (failure) => throw failure,
        );
      },
    );
  }

  Future<void> cleanOldLogs() async {
    final result = await runAsync<int>(
      genericErrorMessage: 'Erro ao limpar logs',
      action: () async {
        final res = await _logService.cleanOldLogs();
        return res.fold(
          (count) => count,
          (failure) => throw failure,
        );
      },
    );
    if (result != null) {
      await refresh();
    }
  }
}
