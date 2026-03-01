import 'dart:convert';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/value_objects/backup_history_state_machine.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/backup_log_repository.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class BackupHistoryRepository implements IBackupHistoryRepository {
  BackupHistoryRepository(this._database, this._backupLogRepository);
  final AppDatabase _database;
  final BackupLogRepository _backupLogRepository;

  @override
  Future<rd.Result<List<BackupHistory>>> getAll({
    int? limit,
    int? offset,
  }) async {
    try {
      final histories = await _database.backupHistoryDao.getAll(
        limit: limit,
        offset: offset,
      );
      final entities = histories.map(_toEntity).toList();
      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar histórico: $e'),
      );
    }
  }

  @override
  Future<rd.Result<BackupHistory>> getById(String id) async {
    try {
      final history = await _database.backupHistoryDao.getById(id);
      if (history == null) {
        return const rd.Failure(
          NotFoundFailure(message: 'Histórico não encontrado'),
        );
      }
      return rd.Success(_toEntity(history));
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar histórico: $e'),
      );
    }
  }

  @override
  Future<rd.Result<BackupHistory>> create(BackupHistory history) async {
    try {
      final companion = _toCompanion(history);
      await _database.backupHistoryDao.insertHistory(companion);
      return rd.Success(history);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao criar histórico: $e'),
      );
    }
  }

  @override
  Future<rd.Result<BackupHistory>> update(BackupHistory history) async {
    try {
      final companion = _toCompanion(history);
      await _database.backupHistoryDao.updateHistory(companion);
      return rd.Success(history);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao atualizar histórico: $e'),
      );
    }
  }

  @override
  Future<rd.Result<BackupHistory>> updateIfRunning(
    BackupHistory history,
  ) async {
    try {
      if (!BackupHistoryStateMachine.isTerminal(history.status)) {
        return rd.Failure(
          ValidationFailure(
            message:
                'updateIfRunning exige status terminal (success, error ou warning). '
                'Recebido: ${history.status.name}.',
          ),
        );
      }
      final companion = _toCompanion(history);
      final updated = await _database.backupHistoryDao.updateHistoryIfRunning(
        companion,
      );
      if (updated == 0) {
        final current = await _database.backupHistoryDao.getById(history.id);
        if (current != null) {
          return rd.Success(_toEntity(current));
        }
      }
      return rd.Success(history);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao atualizar histórico (updateIfRunning): $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<BackupHistory>> updateHistoryAndLogIfRunning({
    required BackupHistory history,
    required String logStep,
    required LogLevel logLevel,
    required String logMessage,
    String? logDetails,
  }) async {
    try {
      if (!BackupHistoryStateMachine.isTerminal(history.status)) {
        return rd.Failure(
          ValidationFailure(
            message:
                'updateHistoryAndLogIfRunning exige status terminal. '
                'Recebido: ${history.status.name}.',
          ),
        );
      }
      await _database.transaction(() async {
        final companion = _toCompanion(history);
        await _database.backupHistoryDao.updateHistoryIfRunning(companion);
        final logCompanion = _backupLogRepository.buildIdempotentLogCompanion(
          backupHistoryId: history.id,
          step: logStep,
          level: logLevel,
          category: LogCategory.execution,
          message: logMessage,
          details: logDetails,
        );
        await _database.backupLogDao.insertOrReplaceLog(logCompanion);
      });
      return rd.Success(history);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao atualizar histórico e log (atômico): $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<void>> delete(String id) async {
    try {
      await _database.backupHistoryDao.deleteHistory(id);
      return const rd.Success(unit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar histórico: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getBySchedule(
    String scheduleId,
  ) async {
    try {
      final histories = await _database.backupHistoryDao.getBySchedule(
        scheduleId,
      );
      final entities = histories.map(_toEntity).toList();
      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao buscar histórico por agendamento: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getByStatus(
    BackupStatus status,
  ) async {
    try {
      final histories = await _database.backupHistoryDao.getByStatus(
        status.name,
      );
      final entities = histories.map(_toEntity).toList();
      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar histórico por status: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    try {
      final histories = await _database.backupHistoryDao.getByDateRange(
        start,
        end,
      );
      final entities = histories.map(_toEntity).toList();
      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar histórico por período: $e'),
      );
    }
  }

  @override
  Future<rd.Result<BackupHistory>> getLastBySchedule(String scheduleId) async {
    try {
      final history = await _database.backupHistoryDao.getLastBySchedule(
        scheduleId,
      );
      if (history == null) {
        return const rd.Failure(
          NotFoundFailure(
            message: 'Nenhum histórico encontrado para este agendamento',
          ),
        );
      }
      return rd.Success(_toEntity(history));
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar último histórico: $e'),
      );
    }
  }

  @override
  Future<rd.Result<int>> deleteOlderThan(DateTime date) async {
    try {
      final count = await _database.backupHistoryDao.deleteOlderThan(date);
      return rd.Success(count);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar históricos antigos: $e'),
      );
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
      backupType: data.backupType,
      status: BackupStatus.values.firstWhere((e) => e.name == data.status),
      errorMessage: data.errorMessage,
      startedAt: data.startedAt,
      finishedAt: data.finishedAt,
      durationSeconds: data.durationSeconds,
      metrics: BackupMetrics.fromJson(data.metrics),
    );
  }

  BackupHistoryTableCompanion _toCompanion(BackupHistory history) {
    final metricsJson = history.metrics?.toJson();
    return BackupHistoryTableCompanion(
      id: Value(history.id),
      scheduleId: Value(history.scheduleId),
      databaseName: Value(history.databaseName),
      databaseType: Value(history.databaseType),
      backupPath: Value(history.backupPath),
      fileSize: Value(history.fileSize),
      backupType: Value(history.backupType),
      status: Value(history.status.name),
      errorMessage: Value(history.errorMessage),
      startedAt: Value(history.startedAt),
      finishedAt: Value(history.finishedAt),
      durationSeconds: Value(history.durationSeconds),
      metrics: Value(metricsJson != null ? jsonEncode(metricsJson) : null),
    );
  }
}
