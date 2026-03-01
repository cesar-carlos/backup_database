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
      return rd.Failure(
        ValidationFailure(
          message:
              'Não foi possível verificar histórico de backup: '
              '${historyResult.exceptionOrNull()}',
        ),
      );
    }

    final histories = historyResult.getOrNull()!;
    final successfulFulls = histories
        .where(
          (h) =>
              (h.backupType == BackupType.full.name ||
                  h.backupType == BackupType.fullSingle.name) &&
              h.status == BackupStatus.success,
        )
        .toList();

    if (successfulFulls.isEmpty) {
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

    successfulFulls.sort(
      (a, b) =>
          (b.finishedAt ?? b.startedAt).compareTo(a.finishedAt ?? a.startedAt),
    );
    final lastFull = successfulFulls.first;
    final lastFullAt = lastFull.finishedAt ?? lastFull.startedAt;
    final daysSinceFull = DateTime.now().difference(lastFullAt).inDays;

    String? warning;
    if (daysSinceFull > _maxDaysForBaseFull) {
      warning =
          'Último backup full expirado há $daysSinceFull dias. '
          'Recomenda-se executar um novo backup full para manter a cadeia de logs.';
      LoggerService.warning('Preflight Sybase log: $warning');
    }

    final lastBackup = histories.isNotEmpty
        ? histories.reduce(
            (a, b) =>
                (a.finishedAt ?? a.startedAt).isAfter(
                  b.finishedAt ?? b.startedAt,
                )
                ? a
                : b,
          )
        : null;
    if (lastBackup != null && lastBackup.status == BackupStatus.error) {
      const chainWarning =
          'Último backup falhou. A cadeia de logs pode estar comprometida.';
      warning = warning != null ? '$warning $chainWarning' : chainWarning;
      LoggerService.warning('Preflight Sybase log: $chainWarning');
    }

    final logsSinceFull = histories
        .where(
          (h) =>
              h.backupType == BackupType.log.name &&
              h.status == BackupStatus.success &&
              (h.finishedAt ?? h.startedAt).isAfter(lastFullAt),
        )
        .length;

    return rd.Success(
      SybaseLogBackupPreflightResult(
        canProceed: true,
        warning: warning,
        baseFull: lastFull,
        nextLogSequence: logsSinceFull + 1,
      ),
    );
  }
}
