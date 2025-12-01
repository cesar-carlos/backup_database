import 'package:flutter/foundation.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/backup_log.dart';
import '../services/log_service.dart';

class LogProvider extends ChangeNotifier {
  final LogService _logService;

  List<BackupLog> _logs = [];
  bool _isLoading = false;
  String? _error;

  // Filtros
  LogLevel? _filterLevel;
  LogCategory? _filterCategory;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String _searchQuery = '';

  // Paginação
  int _currentPage = 0;
  final int _pageSize = 50;
  bool _hasMore = true;

  LogProvider(this._logService);

  List<BackupLog> get logs => _logs;
  bool get isLoading => _isLoading;
  String? get error => _error;
  LogLevel? get filterLevel => _filterLevel;
  LogCategory? get filterCategory => _filterCategory;
  DateTime? get filterStartDate => _filterStartDate;
  DateTime? get filterEndDate => _filterEndDate;
  String get searchQuery => _searchQuery;
  bool get hasMore => _hasMore;
  int get currentPage => _currentPage;
  int get pageSize => _pageSize;

  Future<void> loadLogs({bool append = false}) async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
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
            _logs.addAll(newLogs);
          } else {
            _logs = newLogs;
            _currentPage = 0;
          }
          _hasMore = newLogs.length == _pageSize;
          _error = null;
        },
        (failure) {
          final f = failure as Failure;
          _error = f.message;
        },
      );
    } catch (e) {
      _error = 'Erro ao carregar logs: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoading) return;
    _currentPage++;
    await loadLogs(append: true);
  }

  Future<void> refresh() async {
    _currentPage = 0;
    _hasMore = true;
    await loadLogs(append: false);
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
  }) async {
    try {
      final result = await _logService.exportLogs(
        outputPath: outputPath,
        format: format,
        startDate: _filterStartDate,
        endDate: _filterEndDate,
      );

      return result.fold((filePath) => filePath, (failure) {
        final f = failure as Failure;
        _error = f.message;
        notifyListeners();
        return null;
      });
    } catch (e) {
      _error = 'Erro ao exportar logs: $e';
      notifyListeners();
      return null;
    }
  }

  Future<void> cleanOldLogs() async {
    try {
      final result = await _logService.cleanOldLogs();
      result.fold(
        (count) {
          // Recarregar logs após limpeza
          refresh();
        },
        (failure) {
          final f = failure as Failure;
          _error = f.message;
          notifyListeners();
        },
      );
    } catch (e) {
      _error = 'Erro ao limpar logs: $e';
      notifyListeners();
    }
  }
}
