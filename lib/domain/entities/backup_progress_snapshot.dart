class BackupProgressSnapshot {
  const BackupProgressSnapshot({
    required this.step,
    required this.message,
    this.progress,
    this.backupPath,
    this.error,
  });
  final String step;
  final String message;
  final double? progress;
  final String? backupPath;
  final String? error;
}
