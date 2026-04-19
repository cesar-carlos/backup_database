class BackupProgressSnapshot {
  const BackupProgressSnapshot({
    required this.step,
    required this.message,
    this.progress,
    this.backupPath,
    this.error,
    this.historyId,
  });
  final String step;
  final String message;
  final double? progress;
  final String? backupPath;
  final String? error;

  /// Identificador do `BackupHistory` em curso. Permite que a UI invoque
  /// `IBackupCancellationService.cancelByHistoryId` para abortar o
  /// processo associado ao backup atual.
  final String? historyId;
}
