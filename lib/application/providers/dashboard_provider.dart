import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_metrics_analysis_service.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:flutter/foundation.dart';

class DashboardProvider extends ChangeNotifier {
  DashboardProvider(
    this._backupHistoryRepository,
    this._scheduleRepository, {
    ConnectionManager? connectionManager,
    IMetricsAnalysisService? metricsAnalysisService,
  })  : _connectionManager = connectionManager,
        _metricsAnalysisService = metricsAnalysisService;

  final IBackupHistoryRepository _backupHistoryRepository;
  final IScheduleRepository _scheduleRepository;
  final ConnectionManager? _connectionManager;
  final IMetricsAnalysisService? _metricsAnalysisService;

  static const int _metricsReportDays = 30;

  int _totalBackups = 0;
  int _backupsToday = 0;
  int _failedToday = 0;
  int _activeSchedules = 0;
  List<BackupHistory> _recentBackups = [];
  List<Schedule> _activeSchedulesList = [];
  Map<String, dynamic>? _serverMetrics;
  BackupMetricsReport? _metricsReport;
  bool _isLoading = false;
  String? _error;

  int get totalBackups => _totalBackups;
  int get backupsToday => _backupsToday;
  int get failedToday => _failedToday;
  int get activeSchedules => _activeSchedules;
  List<BackupHistory> get recentBackups => _recentBackups;
  List<Schedule> get activeSchedulesList => _activeSchedulesList;
  Map<String, dynamic>? get serverMetrics => _serverMetrics;
  BackupMetricsReport? get metricsReport => _metricsReport;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadDashboardData() async {
    _isLoading = true;
    _error = null;
    _serverMetrics = null;
    _metricsReport = null;
    notifyListeners();

    try {
      await Future.wait([
        _loadTotalBackups(),
        _loadBackupsToday(),
        _loadFailedToday(),
        _loadActiveSchedules(),
        _loadRecentBackups(),
        _loadMetricsReport(),
      ]);
      if (_connectionManager?.isConnected ?? false) {
        await _loadServerMetrics();
      }
    } on Object catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadMetricsReport() async {
    final service = _metricsAnalysisService;
    if (service == null) return;

    final endDate = DateTime.now();
    final startDate = endDate.subtract(const Duration(days: _metricsReportDays));

    final result = await service.generateReport(
      startDate: startDate,
      endDate: endDate,
    );

    result.fold(
      (report) => _metricsReport = report,
      (_) => _metricsReport = null,
    );
  }

  Future<void> _loadServerMetrics() async {
    final manager = _connectionManager;
    if (manager == null || !manager.isConnected) return;
    final result = await manager.getServerMetrics();
    result.fold(
      (metrics) => _serverMetrics = metrics,
      (_) => _serverMetrics = null,
    );
  }

  Future<void> _loadTotalBackups() async {
    final result = await _backupHistoryRepository.getAll();
    result.fold(
      (backups) {
        _totalBackups = backups.length;
      },
      (failure) {
        final f = failure as Failure;
        _error = f.message;
      },
    );
  }

  Future<void> _loadBackupsToday() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final result = await _backupHistoryRepository.getByDateRange(
      startOfDay,
      endOfDay,
    );
    result.fold(
      (backups) {
        _backupsToday = backups.length;
      },
      (failure) {
        final f = failure as Failure;
        _error ??= f.message;
      },
    );
  }

  Future<void> _loadFailedToday() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final result = await _backupHistoryRepository.getByDateRange(
      startOfDay,
      endOfDay,
    );
    result.fold(
      (backups) {
        _failedToday = backups
            .where((b) => b.status == BackupStatus.error)
            .length;
      },
      (failure) {
        final f = failure as Failure;
        _error ??= f.message;
      },
    );
  }

  Future<void> _loadActiveSchedules() async {
    final result = await _scheduleRepository.getEnabled();
    result.fold(
      (schedules) {
        _activeSchedules = schedules.length;
        _activeSchedulesList = schedules;
      },
      (failure) {
        final f = failure as Failure;
        _error ??= f.message;
      },
    );
  }

  Future<void> _loadRecentBackups() async {
    final result = await _backupHistoryRepository.getAll(limit: 10);
    result.fold(
      (backups) {
        _recentBackups = backups;
      },
      (failure) {
        final f = failure as Failure;
        _error ??= f.message;
      },
    );
  }

  Future<void> refresh() async {
    await loadDashboardData();
  }
}
