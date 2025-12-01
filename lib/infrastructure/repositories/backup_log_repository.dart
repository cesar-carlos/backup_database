import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../core/core.dart';
import '../../domain/entities/backup_log.dart';
import '../../domain/repositories/i_backup_log_repository.dart';
import '../datasources/local/database.dart';

class BackupLogRepository implements IBackupLogRepository {
  final AppDatabase _database;

  BackupLogRepository(this._database);

  @override
  Future<rd.Result<List<BackupLog>>> getAll({int? limit, int? offset}) async {
    try {
      final logs = await _database.backupLogDao.getAll(
        limit: limit,
        offset: offset,
      );
      final entities = logs.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao buscar logs: $e'));
    }
  }

  @override
  Future<rd.Result<BackupLog>> create(BackupLog log) async {
    try {
      final companion = _toCompanion(log);
      await _database.backupLogDao.insertLog(companion);
      return rd.Success(log);
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao criar log: $e'));
    }
  }

  @override
  Future<rd.Result<List<BackupLog>>> getByBackupHistory(
    String backupHistoryId,
  ) async {
    try {
      final logs = await _database.backupLogDao.getByBackupHistory(
        backupHistoryId,
      );
      final entities = logs.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar logs por histórico: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<BackupLog>>> getByLevel(LogLevel level) async {
    try {
      final logs = await _database.backupLogDao.getByLevel(level.name);
      final entities = logs.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar logs por nível: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<BackupLog>>> getByCategory(LogCategory category) async {
    try {
      final logs = await _database.backupLogDao.getByCategory(category.name);
      final entities = logs.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar logs por categoria: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<BackupLog>>> getByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    try {
      final logs = await _database.backupLogDao.getByDateRange(start, end);
      final entities = logs.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar logs por período: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<BackupLog>>> search(String query) async {
    try {
      final logs = await _database.backupLogDao.search(query);
      final entities = logs.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao buscar logs: $e'));
    }
  }

  @override
  Future<rd.Result<int>> deleteOlderThan(DateTime date) async {
    try {
      final count = await _database.backupLogDao.deleteOlderThan(date);
      return rd.Success(count);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar logs antigos: $e'),
      );
    }
  }

  BackupLog _toEntity(BackupLogsTableData data) {
    return BackupLog(
      id: data.id,
      backupHistoryId: data.backupHistoryId,
      level: LogLevel.values.firstWhere((e) => e.name == data.level),
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
