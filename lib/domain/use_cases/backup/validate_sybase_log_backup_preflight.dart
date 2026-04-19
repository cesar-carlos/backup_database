import 'package:backup_database/core/constants/backup_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart'
    show BackupHistory, BackupStatus;
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType, Schedule;
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Result of Sybase log backup preflight validation.
class SybaseLogBackupPreflightResult {
  const SybaseLogBackupPreflightResult({
    required this.canProceed,
    this.error,
    this.warning,
    this.baseFull,
    this.nextLogSequence,
  });

  final bool canProceed;
  final String? error;
  final String? warning;

  /// Last successful full backup (when canProceed). Used for chain metadata.
  final BackupHistory? baseFull;

  /// 1-based sequence of next log in chain (when canProceed and baseFull exists).
  final int? nextLogSequence;
}

/// Validates preflight conditions for Sybase log backup.
///
/// Ensures:
/// - Base full backup exists (last successful full for this schedule);
/// - Last full is not expired (within maxDaysForLogBackupBaseFull);
/// - Emits warning when chain may be broken (e.g. last backup failed).
class ValidateSybaseLogBackupPreflight {
  const ValidateSybaseLogBackupPreflight(
    this._backupHistoryRepository, {
    int maxDaysForBaseFull = BackupConstants.maxDaysForLogBackupBaseFull,
  }) : _maxDaysForBaseFull = maxDaysForBaseFull;

  final IBackupHistoryRepository _backupHistoryRepository;
  final int _maxDaysForBaseFull;

  /// Validates preflight for [schedule] when backup type is log.
  ///
  /// Returns Success with SybaseLogBackupPreflightResult.
  /// - canProceed=false: no full base found — backup must not proceed.
  /// - canProceed=true, warning set: full expired or chain concern — proceed with warning.
  /// - canProceed=true, no warning: proceed normally.
  Future<rd.Result<SybaseLogBackupPreflightResult>> call(
    Schedule schedule,
  ) async {
    if (schedule.databaseType != DatabaseType.sybase) {
      return const rd.Success(SybaseLogBackupPreflightResult(canProceed: true));
    }

    final effectiveType = schedule.backupType == BackupType.fullSingle
        ? BackupType.full
        : schedule.backupType;
    if (effectiveType != BackupType.log) {
      return const rd.Success(SybaseLogBackupPreflightResult(canProceed: true));
    }

    final historyResult = await _backupHistoryRepository.getBySchedule(
      schedule.id,
    );
    if (historyResult.isError()) {
      // Bug histórico: usar `historyResult.exceptionOrNull()` direto na
      // string interpolation gera "Failure(message: ..., code: null)"
      // — feio para o usuário e expõe internals. Extrai `.message` quando
      // for `Failure`.
      final raw = historyResult.exceptionOrNull();
      final detail = raw is Failure ? raw.message : raw?.toString() ?? '';
      return rd.Failure(
        ValidationFailure(
          message: 'Não foi possível verificar histórico de backup: $detail',
        ),
      );
    }

    final histories = historyResult.getOrNull()!;

    // Single-pass classification: antes este método iterava `histories` em
    // 4 passes separados (`successfulFulls.where`, `terminalHistories.where`,
    // `lastBackup.reduce`, `logsSinceFull.where`). Para schedules com
    // muitos backups históricos, isso era O(4N). Agora colapsamos tudo
    // em 1 pass O(N) usando comparações in-place para max.
    final classification = _classifyHistories(histories);

    if (classification.lastFull == null) {
      LoggerService.warning(
        'Preflight Sybase log: nenhum backup full encontrado para '
        'schedule ${schedule.name}',
      );
      return const rd.Success(
        SybaseLogBackupPreflightResult(
          canProceed: false,
          error:
              'Nenhum backup full encontrado para este agendamento. '
              'Execute um backup full antes de backups de log.',
        ),
      );
    }

    final lastFull = classification.lastFull!;
    final lastFullAt = lastFull.finishedAt ?? lastFull.startedAt;
    final daysSinceFull = DateTime.now().difference(lastFullAt).inDays;

    String? warning;
    if (daysSinceFull > _maxDaysForBaseFull) {
      warning =
          'Último backup full expirado há $daysSinceFull dias. '
          'Recomenda-se executar um novo backup full para manter a cadeia de logs.';
      LoggerService.warning('Preflight Sybase log: $warning');
    }

    final lastBackup = classification.lastTerminal;
    if (lastBackup != null && lastBackup.status == BackupStatus.error) {
      const chainWarning =
          'Último backup falhou. A cadeia de logs pode estar comprometida.';
      warning = warning != null ? '$warning $chainWarning' : chainWarning;
      LoggerService.warning('Preflight Sybase log: $chainWarning');
    }

    // `logsSinceFull` precisa do `lastFullAt`, então só conseguimos calcular
    // depois de ter o `lastFull`. Mantemos como segundo pass intencional
    // (agora O(N) total — 1 pass de classificação + 1 de contagem).
    final logsSinceFull = histories.where(_isLogAfter(lastFullAt)).length;

    return rd.Success(
      SybaseLogBackupPreflightResult(
        canProceed: true,
        warning: warning,
        baseFull: lastFull,
        nextLogSequence: logsSinceFull + 1,
      ),
    );
  }

  /// Classifica `histories` em uma única passada O(N) capturando:
  /// - O backup full (ou fullSingle) com sucesso mais recente.
  /// - O backup mais recente em estado terminal (não-running) — usado para
  ///   detectar cadeia comprometida quando o último foi `error`.
  ///
  /// Substitui 3 passes separados (sort, where, reduce) que eram a maior
  /// fonte de O(K·N) deste método em schedules com muitos backups.
  _ClassificationResult _classifyHistories(List<BackupHistory> histories) {
    BackupHistory? lastFull;
    DateTime? lastFullAt;
    BackupHistory? lastTerminal;
    DateTime? lastTerminalAt;

    for (final h in histories) {
      final eventAt = h.finishedAt ?? h.startedAt;

      // Last successful full: aceita `full` e `fullSingle` (compatibilidade
      // com schedules legados que usavam fullSingle como sinônimo).
      if (h.status == BackupStatus.success &&
          (h.backupType == BackupType.full.name ||
              h.backupType == BackupType.fullSingle.name)) {
        if (lastFullAt == null || eventAt.isAfter(lastFullAt)) {
          lastFull = h;
          lastFullAt = eventAt;
        }
      }

      // Last terminal (não-running): protege contra zumbis ainda não
      // reconciliados que poderiam falsamente disparar warning de cadeia
      // quebrada usando `startedAt` como proxy.
      if (h.status != BackupStatus.running) {
        if (lastTerminalAt == null || eventAt.isAfter(lastTerminalAt)) {
          lastTerminal = h;
          lastTerminalAt = eventAt;
        }
      }
    }

    return _ClassificationResult(
      lastFull: lastFull,
      lastTerminal: lastTerminal,
    );
  }

  /// Predicate compilado para o pass de contagem de logs após o último full.
  /// Extraído para evitar capturar `lastFullAt` em closure no hot path.
  bool Function(BackupHistory) _isLogAfter(DateTime lastFullAt) {
    return (h) =>
        h.backupType == BackupType.log.name &&
        h.status == BackupStatus.success &&
        (h.finishedAt ?? h.startedAt).isAfter(lastFullAt);
  }
}

class _ClassificationResult {
  const _ClassificationResult({
    required this.lastFull,
    required this.lastTerminal,
  });
  final BackupHistory? lastFull;
  final BackupHistory? lastTerminal;
}
