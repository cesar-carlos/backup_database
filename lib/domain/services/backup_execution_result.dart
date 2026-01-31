class BackupExecutionResult {
  const BackupExecutionResult({
    required this.backupPath,
    required this.fileSize,
    required this.duration,
    required this.databaseName,
  });
  final String backupPath;
  final int fileSize;
  final Duration duration;
  final String databaseName;
}
