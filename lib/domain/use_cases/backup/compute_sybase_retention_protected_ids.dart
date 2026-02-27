import 'package:backup_database/domain/entities/backup_history.dart'
    show BackupHistory, BackupStatus;

/// Computes which backup IDs must be retained for Sybase schedules
/// to preserve restorable full+log chains.
///
/// Policy: retain full backup + all logs until next full.
/// Chains older than `retentionDays` may be deleted only when superseded
/// by a newer full.
class ComputeSybaseRetentionProtectedIds {
  const ComputeSybaseRetentionProtectedIds();

  /// Returns the set of backup IDs that must not be deleted.
  ///
  /// [histories] must be successful backups for a Sybase schedule,
  /// ordered by startedAt ascending (oldest first).
  /// [retentionDays] defines the retention window.
  Set<String> call({
    required List<BackupHistory> histories,
    required int retentionDays,
  }) {
    if (histories.isEmpty) return const {};

    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    final successful = histories
        .where((h) => h.status == BackupStatus.success)
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    final fulls = successful
        .where((h) =>
            h.backupType == 'full' || h.backupType == 'full_single')
        .toList();
    final logs = successful.where((h) => h.backupType == 'log').toList();

    final protected = <String>{};

    for (final full in fulls) {
      final fullFinishedAt = full.finishedAt ?? full.startedAt;
      final logsForFull = logs
          .where((l) => _baseFullId(l) == full.id)
          .map((l) => l.id)
          .toSet();

      final chainIds = {full.id, ...logsForFull};

      final isWithinRetention = fullFinishedAt.isAfter(cutoff);
      final isLastFull = full == fulls.last;

      if (isWithinRetention || isLastFull) {
        protected.addAll(chainIds);
      }
    }

    return protected;
  }

  String? _baseFullId(BackupHistory h) {
    final opts = h.metrics?.sybaseOptions;
    if (opts == null) return null;
    return opts['baseFullId'] as String?;
  }
}
