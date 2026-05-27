class BackupProgressSnapshot {
  const BackupProgressSnapshot({
    required this.step,
    required this.message,
    this.progress,
    this.backupPath,
    this.error,
    this.historyId,
    this.cancelled = false,
    this.cancelReason,
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

  /// PR-6: `true` quando a terminacao foi por cancelamento explicito
  /// (operador via `cancelBackup`) em vez de falha tecnica. Permite que
  /// a UI / o `ScheduleMessageHandler` emita evento `backupCancelled`
  /// distinto de `backupFailed`.
  final bool cancelled;

  /// Motivo do cancelamento (ex.: 'watchdog timeout', 'hard limit',
  /// 'operador'). Apenas relevante quando [cancelled] e `true`.
  final String? cancelReason;
}
