import 'package:backup_database/core/logging/log_context.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class BackupLogRepository implements IBackupLogRepository {
  BackupLogRepository(this._database);
  final AppDatabase _database;

  @override
  Future<rd.Result<List<BackupLog>>> getAll({int? limit, int? offset}) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar logs',
      action: () async {
        final logs = await _database.backupLogDao.getAll(
          limit: limit,
          offset: offset,
        );
        return logs.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<BackupLog>> create(BackupLog log) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao criar log',
      action: () async {
        await _database.backupLogDao.insertLog(_toCompanion(log));
        return log;
      },
    );
  }

  static String _sanitizeStep(String step) {
    final sanitized = step.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
    return sanitized.length > 80 ? sanitized.substring(0, 80) : sanitized;
  }

  BackupLogsTableCompanion buildIdempotentLogCompanion({
    required String backupHistoryId,
    required String step,
    required LogLevel level,
    required LogCategory category,
    required String message,
    String? details,
  }) {
    final id = '${backupHistoryId}_${_sanitizeStep(step)}';
    final enrichedDetails = _detailsWithContext(details);
    final log = BackupLog(
      id: id,
      backupHistoryId: backupHistoryId,
      level: level,
      category: category,
      message: message,
      details: enrichedDetails,
    );
    return _toCompanion(log);
  }

  static String? _detailsWithContext(String? details) {
    if (!LogContext.hasContext) return details;
    final ctx = 'runId=${LogContext.runId} scheduleId=${LogContext.scheduleId}';
    return details != null ? '$details | $ctx' : ctx;
  }

  @override
  Future<rd.Result<BackupLog>> createIdempotent({
    required String backupHistoryId,
    required String step,
    required LogLevel level,
    required LogCategory category,
    required String message,
    String? details,
  }) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao criar log idempotente',
      action: () async {
        final id = '${backupHistoryId}_${_sanitizeStep(step)}';
        final enrichedDetails = _detailsWithContext(details);
        final log = BackupLog(
          id: id,
          backupHistoryId: backupHistoryId,
          level: level,
          category: category,
          message: message,
          details: enrichedDetails,
        );
        await _database.backupLogDao.insertOrReplaceLog(_toCompanion(log));
        return log;
      },
    );
  }

  @override
  Future<rd.Result<List<BackupLog>>> getByBackupHistory(
    String backupHistoryId,
  ) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar logs por histórico',
      action: () async {
        final logs = await _database.backupLogDao.getByBackupHistory(
          backupHistoryId,
        );
        return logs.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<List<BackupLog>>> getByLevel(LogLevel level) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar logs por nível',
      action: () async {
        final logs = await _database.backupLogDao.getByLevel(level.name);
        return logs.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<List<BackupLog>>> getByCategory(LogCategory category) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar logs por categoria',
      action: () async {
        final logs = await _database.backupLogDao.getByCategory(category.name);
        return logs.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<List<BackupLog>>> getByDateRange(
    DateTime start,
    DateTime end,
  ) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar logs por período',
      action: () async {
        final logs = await _database.backupLogDao.getByDateRange(start, end);
        return logs.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<List<BackupLog>>> search(String query) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar logs',
      action: () async {
        final logs = await _database.backupLogDao.search(query);
        return logs.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<int>> deleteOlderThan(DateTime date) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao deletar logs antigos',
      action: () => _database.backupLogDao.deleteOlderThan(date),
    );
  }

  BackupLog _toEntity(BackupLogsTableData data) {
    return BackupLog(
      id: data.id,
      backupHistoryId: data.backupHistoryId,
      level: LogLevel.fromString(data.level),
      category: LogCategory.values.firstWhere((e) => e.name == data.category),
      message: data.message,
      details: data.details,
      createdAt: data.createdAt,
    );
  }

  BackupLogsTableCompanion _toCompanion(BackupLog log) {
    return BackupLogsTableCompanion(
      id: Value(log.id),
      backupHistoryId: Value(log.backupHistoryId),
      level: Value(log.level.name),
      category: Value(log.category.name),
      message: Value(log.message),
      details: Value(log.details),
      createdAt: Value(log.createdAt),
    );
  }
}
