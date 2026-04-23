import 'dart:convert';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/value_objects/backup_history_state_machine.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/backup_log_repository.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class BackupHistoryRepository implements IBackupHistoryRepository {
  BackupHistoryRepository(this._database, this._backupLogRepository);
  final AppDatabase _database;
  final BackupLogRepository _backupLogRepository;

  @override
  Future<rd.Result<List<BackupHistory>>> getAll({int? limit, int? offset}) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar histórico',
      action: () async {
        final histories = await _database.backupHistoryDao.getAll(
          limit: limit,
          offset: offset,
        );
        return histories.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<BackupHistory>> getById(String id) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar histórico',
      action: () async {
        final history = await _database.backupHistoryDao.getById(id);
        if (history == null) {
          // `NotFoundFailure` é um `Failure`, então o `RepositoryGuard.run`
          // o propaga sem reembrulhar (ver branch `on Failure catch`).
          throw const NotFoundFailure(message: 'Histórico não encontrado');
        }
        return _toEntity(history);
      },
    );
  }

  @override
  Future<rd.Result<BackupHistory>> getByRunId(String runId) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar histórico por runId',
      action: () async {
        final history = await _database.backupHistoryDao.getByRunId(runId);
        if (history == null) {
          throw const NotFoundFailure(message: 'Histórico não encontrado');
        }
        return _toEntity(history);
      },
    );
  }

  @override
  Future<rd.Result<BackupHistory>> create(BackupHistory history) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao criar histórico',
      action: () async {
        await _database.backupHistoryDao.insertHistory(_toCompanion(history));
        return history;
      },
    );
  }

  @override
  Future<rd.Result<BackupHistory>> update(BackupHistory history) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao atualizar histórico',
      action: () async {
        // Valida a transição de estado antes de gravar para evitar regressões
        // (ex.: success → running) que tornariam o histórico inconsistente.
        // A validação é melhor-esforço: se o registro não existir ainda no
        // banco, simplesmente cai para o `replace` normal.
        final current = await _database.backupHistoryDao.getById(history.id);
        if (current != null) {
          final currentStatus = _statusFromString(
            current.status,
            fallbackId: current.id,
          );
          if (!BackupHistoryStateMachine.canTransition(
            currentStatus,
            history.status,
          )) {
            // Lançar uma `ValidationFailure` (que é um `Failure`) faz o
            // `RepositoryGuard.run` propagá-la diretamente sem wrappar
            // em `DatabaseFailure`. Mantemos a semântica original.
            throw ValidationFailure(
              message:
                  'Transição de status inválida para histórico ${history.id}: '
                  '${currentStatus.name} → ${history.status.name}.',
            );
          }
        }
        await _database.backupHistoryDao.updateHistory(_toCompanion(history));
        return history;
      },
    );
  }

  @override
  Future<rd.Result<BackupHistory>> updateIfRunning(BackupHistory history) {
    if (!BackupHistoryStateMachine.isTerminal(history.status)) {
      return Future.value(
        rd.Failure(
          ValidationFailure(
            message:
                'updateIfRunning exige status terminal (success, error ou warning). '
                'Recebido: ${history.status.name}.',
          ),
        ),
      );
    }
    return RepositoryGuard.run(
      errorMessage: 'Erro ao atualizar histórico (updateIfRunning)',
      action: () async {
        final updated = await _database.backupHistoryDao
            .updateHistoryIfRunning(_toCompanion(history));
        if (updated == 0) {
          // Quando o registro já saiu de `running`, lê o estado real para
          // devolver ao caller — preserva o comportamento original.
          final current = await _database.backupHistoryDao.getById(history.id);
          if (current != null) return _toEntity(current);
        }
        return history;
      },
    );
  }

  @override
  Future<rd.Result<BackupHistory>> updateHistoryAndLogIfRunning({
    required BackupHistory history,
    required String logStep,
    required LogLevel logLevel,
    required String logMessage,
    String? logDetails,
  }) {
    if (!BackupHistoryStateMachine.isTerminal(history.status)) {
      return Future.value(
        rd.Failure(
          ValidationFailure(
            message:
                'updateHistoryAndLogIfRunning exige status terminal. '
                'Recebido: ${history.status.name}.',
          ),
        ),
      );
    }
    return RepositoryGuard.run(
      errorMessage: 'Erro ao atualizar histórico e log (atômico)',
      action: () async {
        var updatedRows = 0;
        await _database.transaction(() async {
          final companion = _toCompanion(history);
          updatedRows = await _database.backupHistoryDao
              .updateHistoryIfRunning(companion);
          if (updatedRows == 0) return;
          final logCompanion =
              _backupLogRepository.buildIdempotentLogCompanion(
            backupHistoryId: history.id,
            step: logStep,
            level: logLevel,
            category: LogCategory.execution,
            message: logMessage,
            details: logDetails,
          );
          await _database.backupLogDao.insertOrReplaceLog(logCompanion);
        });
        if (updatedRows == 0) {
          throw ValidationFailure(
            message:
                'Histórico não estava em execução (status running); '
                'não foi possível aplicar log: $logStep',
          );
        }
        return history;
      },
    );
  }

  @override
  Future<rd.Result<void>> delete(String id) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao deletar histórico',
      action: () => _database.backupHistoryDao.deleteHistory(id),
    );
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getBySchedule(String scheduleId) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar histórico por agendamento',
      action: () async {
        final histories =
            await _database.backupHistoryDao.getBySchedule(scheduleId);
        return histories.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getByStatus(BackupStatus status) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar histórico por status',
      action: () async {
        final histories =
            await _database.backupHistoryDao.getByStatus(status.name);
        return histories.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getByDateRange(
    DateTime start,
    DateTime end,
  ) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar histórico por período',
      action: () async {
        final histories =
            await _database.backupHistoryDao.getByDateRange(start, end);
        return histories.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<BackupHistory>> getLastBySchedule(String scheduleId) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar último histórico',
      action: () async {
        final history =
            await _database.backupHistoryDao.getLastBySchedule(scheduleId);
        if (history == null) {
          throw const NotFoundFailure(
            message: 'Nenhum histórico encontrado para este agendamento',
          );
        }
        return _toEntity(history);
      },
    );
  }

  @override
  Future<rd.Result<int>> deleteOlderThan(DateTime date) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao deletar históricos antigos',
      action: () => _database.backupHistoryDao.deleteOlderThan(date),
    );
  }

  @override
  Future<rd.Result<int>> reconcileStaleRunning({required Duration maxAge}) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao reconciliar históricos running antigos',
      action: () async {
        final cutoff = DateTime.now().subtract(maxAge);
        final rows =
            await _database.backupHistoryDao.getRunningStartedBefore(cutoff);
        if (rows.isEmpty) return 0;

        const message =
            'Backup interrompido: processo encerrado durante a execução '
            '(recuperação ao iniciar o agendador).';

        // Envolve todos os updates em uma transação para garantir
        // atomicidade (`reconcileStaleRunning` não pode deixar parte dos
        // jobs zumbis em estado intermediário se o app cair no meio).
        var updated = 0;
        await _database.transaction(() async {
          for (final row in rows) {
            final entity = _toEntity(row);
            final finishedAt = DateTime.now();
            final reconciled = entity.copyWith(
              status: BackupStatus.error,
              errorMessage: message,
              finishedAt: finishedAt,
              durationSeconds:
                  finishedAt.difference(entity.startedAt).inSeconds,
            );
            final companion = _toCompanion(reconciled);
            final ok =
                await _database.backupHistoryDao.updateHistory(companion);
            if (ok) updated++;
          }
        });
        return updated;
      },
    );
  }

  BackupHistory _toEntity(BackupHistoryTableData data) {
    return BackupHistory(
      id: data.id,
      runId: data.runId,
      scheduleId: data.scheduleId,
      databaseName: data.databaseName,
      databaseType: data.databaseType,
      backupPath: data.backupPath,
      fileSize: data.fileSize,
      backupType: data.backupType,
      status: _statusFromString(data.status, fallbackId: data.id),
      errorMessage: data.errorMessage,
      startedAt: data.startedAt,
      finishedAt: data.finishedAt,
      durationSeconds: data.durationSeconds,
      metrics: BackupMetrics.fromJson(data.metrics),
    );
  }

  /// Converte a string persistida em [BackupStatus] tolerando dados legados.
  /// Em vez de lançar [StateError] quando o valor não corresponde a nenhum
  /// caso atual, registra um warning e retorna [BackupStatus.error] para que
  /// o resto do histórico ainda possa ser lido.
  BackupStatus _statusFromString(String value, {required String fallbackId}) {
    for (final status in BackupStatus.values) {
      if (status.name == value) return status;
    }
    LoggerService.warning(
      'BackupHistory $fallbackId com status desconhecido "$value"; '
      'tratando como "error".',
    );
    return BackupStatus.error;
  }

  BackupHistoryTableCompanion _toCompanion(BackupHistory history) {
    final metricsJson = history.metrics?.toJson();
    return BackupHistoryTableCompanion(
      id: Value(history.id),
      runId: Value(history.runId),
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
