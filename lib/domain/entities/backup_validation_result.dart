class BackupValidationResult {
  const BackupValidationResult({
    required this.isValid,
    required this.fileSize,
    required this.lastModified,
    this.error,
  });
  final bool isValid;
  final int fileSize;
  final DateTime lastModified;
  final String? error;
}
