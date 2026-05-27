import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/infrastructure/datasources/cache/query_cache.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Decorator que adiciona cache de consultas list ao
/// [IBackupHistoryRepository] subjacente (TTL padrão: 2 minutos).
///
/// **Modelo de invalidação — version token (TOCTOU-safe)**:
///
/// O cache antigo sofria de race entre leitura assíncrona e write
/// concorrente:
/// 1. Coroutine A: cache miss → inicia `_repository.getAll()` (snapshot).
/// 2. Coroutine B: `create`/`update`/`delete` → `_cache.clear()`.
/// 3. Coroutine A: completa e faz `_cache.put(...)` com dados anteriores
///    ao write de B → UI vê dados stale por até 2 min.
///
/// Solução: cada `clear()` incrementa `_cacheVersion`. Antes de cada
/// leitura, anotamos a versão; só fazemos `put` se ela não mudou.
/// Também clonamos a lista para evitar alias do cache com a referência
/// retornada (mutação in-place do caller corrompia o cache).
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
  int _cacheVersion = 0;

  void _invalidate() {
    _cacheVersion++;
    _cache.clear();
  }

  /// Wrap genérico das leituras list: usa cached se houver, senão
  /// delega ao repo e cacheia o resultado apenas se nenhum write
  /// ocorreu enquanto a leitura estava em andamento (version match).
  Future<rd.Result<List<BackupHistory>>> _readCached(
    String cacheKey,
    Future<rd.Result<List<BackupHistory>>> Function() loader,
  ) async {
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      // Retorna cópia para que mutações do caller não corrompam o cache.
      return rd.Success(List<BackupHistory>.unmodifiable(cached));
    }

    final versionAtRead = _cacheVersion;
    final result = await loader();
    return result.fold(
      (historyList) {
        // Só persiste se nenhum write invalidou o cache durante a leitura.
        final immutable = List<BackupHistory>.unmodifiable(historyList);
        if (_cacheVersion == versionAtRead) {
          _cache.put(cacheKey, immutable);
        }
        // Sempre retorna versão imutável para evitar mutação acidental
        // do consumidor que corromperia o cache.
        return rd.Success(immutable);
      },
      rd.Failure.new,
    );
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getAll({
    int? limit,
    int? offset,
  }) {
    return _readCached(
      'all_${limit ?? "all"}_${offset ?? 0}',
      () => _repository.getAll(limit: limit, offset: offset),
    );
  }

  @override
  Future<rd.Result<BackupHistory>> getById(String id) async {
    // Don't cache single item queries
    return _repository.getById(id);
  }

  @override
  Future<rd.Result<BackupHistory>> getByRunId(String runId) {
    return _repository.getByRunId(runId);
  }

  @override
  Future<rd.Result<BackupHistory>> create(BackupHistory history) async {
    final result = await _repository.create(history);
    _invalidate();
    return result;
  }

  @override
  Future<rd.Result<BackupHistory>> update(BackupHistory history) async {
    final result = await _repository.update(history);
    _invalidate();
    return result;
  }

  @override
  Future<rd.Result<BackupHistory>> updateIfRunning(
    BackupHistory history,
  ) async {
    final result = await _repository.updateIfRunning(history);
    if (result.isSuccess()) {
      _invalidate();
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
      _invalidate();
    }
    return result;
  }

  @override
  Future<rd.Result<void>> delete(String id) async {
    final result = await _repository.delete(id);
    _invalidate();
    return result;
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getBySchedule(String scheduleId) {
    return _readCached(
      'schedule_$scheduleId',
      () => _repository.getBySchedule(scheduleId),
    );
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getByStatus(BackupStatus status) {
    return _readCached(
      'status_${status.name}',
      () => _repository.getByStatus(status),
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
    _invalidate();
    return result;
  }

  @override
  Future<rd.Result<int>> reconcileStaleRunning({
    required Duration maxAge,
  }) async {
    final result = await _repository.reconcileStaleRunning(maxAge: maxAge);
    result.fold(
      (count) {
        if (count > 0) {
          _invalidate();
        }
      },
      (_) {},
    );
    return result;
  }

  /// Limpa todo o cache. Usado por testes e teardown.
  void clearCache() {
    _invalidate();
  }
}
