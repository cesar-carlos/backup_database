import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/infrastructure/datasources/cache/query_cache.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Cached implementation of BackupHistoryRepository
/// Caches list queries for 2 minutes to reduce database load
class CachedBackupHistoryRepository implements IBackupHistoryRepository {
  CachedBackupHistoryRepository({
    required IBackupHistoryRepository repository,
    Duration? cacheTtl,
  }) : _repository = repository,
       _cache = QueryCache<List<BackupHistory>>(
         ttl: cacheTtl ?? const Duration(minutes: 2),
       );

  final IBackupHistoryRepository _repository;
  final QueryCache<List<BackupHistory>> _cache;

  @override
  Future<rd.Result<List<BackupHistory>>> getAll({
    int? limit,
    int? offset,
  }) async {
    final cacheKey = 'all_${limit ?? "all"}_${offset ?? 0}';
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      return rd.Success(cached);
    }

    final result = await _repository.getAll(limit: limit, offset: offset);
    return result.fold(
      (historyList) {
        _cache.put(cacheKey, historyList);
        return rd.Success(historyList);
      },
      rd.Failure.new,
    );
  }

  @override
  Future<rd.Result<BackupHistory>> getById(String id) async {
    // Don't cache single item queries
    return _repository.getById(id);
  }

  @override
  Future<rd.Result<BackupHistory>> create(BackupHistory history) async {
    final result = await _repository.create(history);
    // Invalidate cache on create
    _cache.clear();
    return result;
  }

  @override
  Future<rd.Result<BackupHistory>> update(BackupHistory history) async {
    final result = await _repository.update(history);
    // Invalidate cache on update
    _cache.clear();
    return result;
  }

  @override
  Future<rd.Result<BackupHistory>> updateIfRunning(
    BackupHistory history,
  ) async {
    final result = await _repository.updateIfRunning(history);
    if (result.isSuccess()) {
      _cache.clear();
    }
    return result;
  }

  @override
  Future<rd.Result<BackupHistory>> updateHistoryAndLogIfRunning({
    required BackupHistory history,
    required String logStep,
    required LogLevel logLevel,
    required String logMessage,
    String? logDetails,
  }) async {
    final result = await _repository.updateHistoryAndLogIfRunning(
      history: history,
      logStep: logStep,
      logLevel: logLevel,
      logMessage: logMessage,
      logDetails: logDetails,
    );
    if (result.isSuccess()) {
      _cache.clear();
    }
    return result;
  }

  @override
  Future<rd.Result<void>> delete(String id) async {
    final result = await _repository.delete(id);
    // Invalidate cache on delete
    _cache.clear();
    return result;
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getBySchedule(
    String scheduleId,
  ) async {
    final cacheKey = 'schedule_$scheduleId';
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      return rd.Success(cached);
    }

    final result = await _repository.getBySchedule(scheduleId);
    return result.fold(
      (historyList) {
        _cache.put(cacheKey, historyList);
        return rd.Success(historyList);
      },
      rd.Failure.new,
    );
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getByStatus(
    BackupStatus status,
  ) async {
    final cacheKey = 'status_${status.name}';
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      return rd.Success(cached);
    }

    final result = await _repository.getByStatus(status);
    return result.fold(
      (historyList) {
        _cache.put(cacheKey, historyList);
        return rd.Success(historyList);
      },
      rd.Failure.new,
    );
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    // Don't cache date range queries as they're highly variable
    return _repository.getByDateRange(start, end);
  }

  @override
  Future<rd.Result<BackupHistory>> getLastBySchedule(String scheduleId) async {
    // Don't cache single item queries
    return _repository.getLastBySchedule(scheduleId);
  }

  @override
  Future<rd.Result<int>> deleteOlderThan(DateTime date) async {
    final result = await _repository.deleteOlderThan(date);
    // Invalidate cache on delete
    _cache.clear();
    return result;
  }

  /// Clear all cached data
  void clearCache() {
    _cache.clear();
  }
}
