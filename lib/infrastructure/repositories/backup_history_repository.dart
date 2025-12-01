import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../core/core.dart';
import '../../domain/entities/backup_history.dart';
import '../../domain/repositories/i_backup_history_repository.dart';
import '../datasources/local/database.dart';

class BackupHistoryRepository implements IBackupHistoryRepository {
  final AppDatabase _database;

  BackupHistoryRepository(this._database);

  @override
  Future<rd.Result<List<BackupHistory>>> getAll({int? limit, int? offset}) async {
    try {
      final histories = await _database.backupHistoryDao.getAll(limit: limit, offset: offset);
      final entities = histories.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao buscar histórico: $e'));
    }
  }

  @override
  Future<rd.Result<BackupHistory>> getById(String id) async {
    try {
      final history = await _database.backupHistoryDao.getById(id);
      if (history == null) {
        return rd.Failure(
          NotFoundFailure(message: 'Histórico não encontrado'),
        );
      }
      return rd.Success(_toEntity(history));
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao buscar histórico: $e'));
    }
  }

  @override
  Future<rd.Result<BackupHistory>> create(BackupHistory history) async {
    try {
      final companion = _toCompanion(history);
      await _database.backupHistoryDao.insertHistory(companion);
      return rd.Success(history);
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao criar histórico: $e'));
    }
  }

  @override
  Future<rd.Result<BackupHistory>> update(BackupHistory history) async {
    try {
      final companion = _toCompanion(history);
      await _database.backupHistoryDao.updateHistory(companion);
      return rd.Success(history);
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao atualizar histórico: $e'));
    }
  }

  @override
  Future<rd.Result<void>> delete(String id) async {
    try {
      await _database.backupHistoryDao.deleteHistory(id);
      return const rd.Success(unit);
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao deletar histórico: $e'));
    }
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getBySchedule(String scheduleId) async {
    try {
      final histories = await _database.backupHistoryDao.getBySchedule(scheduleId);
      final entities = histories.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao buscar histórico por agendamento: $e'));
    }
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getByStatus(BackupStatus status) async {
    try {
      final histories = await _database.backupHistoryDao.getByStatus(status.name);
      final entities = histories.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao buscar histórico por status: $e'));
    }
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getByDateRange(DateTime start, DateTime end) async {
    try {
      final histories = await _database.backupHistoryDao.getByDateRange(start, end);
      final entities = histories.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao buscar histórico por período: $e'));
    }
  }

  @override
  Future<rd.Result<BackupHistory>> getLastBySchedule(String scheduleId) async {
    try {
      final history = await _database.backupHistoryDao.getLastBySchedule(scheduleId);
      if (history == null) {
        return rd.Failure(
          NotFoundFailure(message: 'Nenhum histórico encontrado para este agendamento'),
        );
      }
      return rd.Success(_toEntity(history));
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao buscar último histórico: $e'));
    }
  }

  @override
  Future<rd.Result<int>> deleteOlderThan(DateTime date) async {
    try {
      final count = await _database.backupHistoryDao.deleteOlderThan(date);
      return rd.Success(count);
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao deletar históricos antigos: $e'));
    }
  }

  BackupHistory _toEntity(BackupHistoryTableData data) {
    return BackupHistory(
      id: data.id,
      scheduleId: data.scheduleId,
      databaseName: data.databaseName,
      databaseType: data.databaseType,
      backupPath: data.backupPath,
      fileSize: data.fileSize,
      status: BackupStatus.values.firstWhere((e) => e.name == data.status),
      errorMessage: data.errorMessage,
      startedAt: data.startedAt,
      finishedAt: data.finishedAt,
      durationSeconds: data.durationSeconds,
    );
  }

  BackupHistoryTableCompanion _toCompanion(BackupHistory history) {
    return BackupHistoryTableCompanion(
      id: Value(history.id),
      scheduleId: Value(history.scheduleId),
      databaseName: Value(history.databaseName),
      databaseType: Value(history.databaseType),
      backupPath: Value(history.backupPath),
      fileSize: Value(history.fileSize),
      status: Value(history.status.name),
      errorMessage: Value(history.errorMessage),
      startedAt: Value(history.startedAt),
      finishedAt: Value(history.finishedAt),
      durationSeconds: Value(history.durationSeconds),
    );
  }
}
