import 'package:backup_database/core/constants/backup_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Status agregado da cadeia de backups Sybase.
///
/// - `ok`: cadeia íntegra, último full dentro da janela aceitável.
/// - `warning`: full expirado ou último backup falhou.
/// - `broken`: existem logs sem nenhum full base — restore inviável.
enum SybaseChainStatus { ok, warning, broken }

class SybaseBackupHealth {
  const SybaseBackupHealth({
    required this.lastFull,
    required this.lastLog,
    required this.chainStatus,
  });

  final BackupHistory? lastFull;
  final BackupHistory? lastLog;
  final SybaseChainStatus chainStatus;
}

/// Calcula a saúde dos backups Sybase a partir do histórico.
///
/// Substitui a duplicação de lógica entre `SybaseBackupHealthCard`
/// (presentation) e `ValidateSybaseLogBackupPreflight` (domain), garantindo
/// que a regra de "cadeia OK / warning / broken" viva num único lugar.
///
/// Single-pass O(N) sobre o histórico (mesma estratégia do preflight),
/// substituindo as 3 ordenações com `where().toList()..sort()` que o
/// widget fazia.
class GetSybaseBackupHealth {
  const GetSybaseBackupHealth(
    this._historyRepository, {
    int maxDaysForBaseFull = BackupConstants.maxDaysForLogBackupBaseFull,
    int historyLimit = 200,
  }) : _maxDaysForBaseFull = maxDaysForBaseFull,
       _historyLimit = historyLimit;

  final IBackupHistoryRepository _historyRepository;
  final int _maxDaysForBaseFull;
  final int _historyLimit;

  Future<rd.Result<SybaseBackupHealth>> call() async {
    final result = await _historyRepository.getAll(limit: _historyLimit);
    if (result.isError()) {
      final ex = result.exceptionOrNull();
      return rd.Failure(
        ex is Failure
            ? ex
            : DatabaseFailure(
                message:
                    'Falha ao carregar histórico Sybase: ${ex ?? "erro desconhecido"}',
                originalError: ex ?? '',
              ),
      );
    }

    final histories = result.getOrNull() ?? const <BackupHistory>[];
    return rd.Success(_classify(histories));
  }

  SybaseBackupHealth _classify(List<BackupHistory> histories) {
    BackupHistory? lastFull;
    DateTime? lastFullAt;
    BackupHistory? lastLog;
    DateTime? lastLogAt;
    BackupHistory? lastTerminal;
    DateTime? lastTerminalAt;

    for (final h in histories) {
      if (h.databaseType.toLowerCase() != 'sybase') continue;
      final eventAt = h.finishedAt ?? h.startedAt;

      // Full bem-sucedido (aceita `full` e `fullSingle` por compatibilidade
      // com schedules legados).
      if (h.status == BackupStatus.success &&
          (h.backupType == BackupType.full.name ||
              h.backupType == BackupType.fullSingle.name)) {
        if (lastFullAt == null || eventAt.isAfter(lastFullAt)) {
          lastFull = h;
          lastFullAt = eventAt;
        }
      }

      // Log bem-sucedido.
      if (h.status == BackupStatus.success &&
          h.backupType == BackupType.log.name) {
        if (lastLogAt == null || eventAt.isAfter(lastLogAt)) {
          lastLog = h;
          lastLogAt = eventAt;
        }
      }

      // Último estado terminal (sucesso ou erro) para detectar cadeia
      // comprometida quando o backup mais recente foi `error`.
      if (h.status != BackupStatus.running) {
        if (lastTerminalAt == null || eventAt.isAfter(lastTerminalAt)) {
          lastTerminal = h;
          lastTerminalAt = eventAt;
        }
      }
    }

    final status = _resolveStatus(
      lastFull: lastFull,
      lastFullAt: lastFullAt,
      lastLog: lastLog,
      lastTerminal: lastTerminal,
    );

    return SybaseBackupHealth(
      lastFull: lastFull,
      lastLog: lastLog,
      chainStatus: status,
    );
  }

  SybaseChainStatus _resolveStatus({
    required BackupHistory? lastFull,
    required DateTime? lastFullAt,
    required BackupHistory? lastLog,
    required BackupHistory? lastTerminal,
  }) {
    // Existem logs mas nenhum full base — restore inviável.
    if (lastFull == null && lastLog != null) {
      return SybaseChainStatus.broken;
    }
    if (lastFull == null) {
      return SybaseChainStatus.ok;
    }

    final daysSinceFull = DateTime.now().difference(lastFullAt!).inDays;
    if (daysSinceFull > _maxDaysForBaseFull) {
      return SybaseChainStatus.warning;
    }
    if (lastTerminal?.status == BackupStatus.error) {
      return SybaseChainStatus.warning;
    }
    return SybaseChainStatus.ok;
  }
}
