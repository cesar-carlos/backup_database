import 'package:flutter/foundation.dart';

import '../../core/core.dart';
import '../../domain/entities/backup_history.dart';
import '../../domain/entities/schedule.dart';
import '../../domain/repositories/i_backup_history_repository.dart';
import '../../domain/repositories/i_schedule_repository.dart';

class DashboardProvider extends ChangeNotifier {
  final IBackupHistoryRepository _backupHistoryRepository;
  final IScheduleRepository _scheduleRepository;

  DashboardProvider(this._backupHistoryRepository, this._scheduleRepository);

  int _totalBackups = 0;
  int _backupsToday = 0;
  int _failedToday = 0;
  int _activeSchedules = 0;
  List<BackupHistory> _recentBackups = [];
  List<Schedule> _activeSchedulesList = [];
  bool _isLoading = false;
  String? _error;

  int get totalBackups => _totalBackups;
  int get backupsToday => _backupsToday;
  int get failedToday => _failedToday;
  int get activeSchedules => _activeSchedules;
  List<BackupHistory> get recentBackups => _recentBackups;
  List<Schedule> get activeSchedulesList => _activeSchedulesList;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadDashboardData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.wait([
        _loadTotalBackups(),
        _loadBackupsToday(),
        _loadFailedToday(),
        _loadActiveSchedules(),
        _loadRecentBackups(),
      ]);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
