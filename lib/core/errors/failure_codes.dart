class FailureCodes {
  FailureCodes._();

  static const String backupFailed = 'BACKUP_FAILED';
  static const String backupCancelled = 'BACKUP_CANCELLED';
  static const String backupTimeout = 'BACKUP_TIMEOUT';
  static const String backupDbError = 'BACKUP_DB_ERROR';
  static const String backupFileNotFound = 'BACKUP_FILE_NOT_FOUND';
  static const String uploadFailed = 'UPLOAD_FAILED';
  static const String uploadCancelled = 'UPLOAD_CANCELLED';
  static const String circuitBreakerOpen = 'CIRCUIT_BREAKER_OPEN';
  static const String validationFailed = 'VALIDATION_FAILED';
  static const String invalidInput = 'INVALID_INPUT';
  static const String networkError = 'NETWORK_ERROR';
  static const String timeout = 'TIMEOUT';
  static const String connectionRefused = 'CONNECTION_REFUSED';
  static const String diskFull = 'DISK_FULL';
  static const String permissionDenied = 'PERMISSION_DENIED';
  static const String fileNotFound = 'FILE_NOT_FOUND';
  static const String configNotFound = 'CONFIG_NOT_FOUND';
  static const String licenseDenied = 'LICENSE_DENIED';
  static const String databaseError = 'DATABASE_ERROR';
  static const String compressionFailed = 'COMPRESSION_FAILED';
  static const String scheduleNotFound = 'SCHEDULE_NOT_FOUND';
  static const String scheduleAlreadyRunning = 'SCHEDULE_ALREADY_RUNNING';
  static const String cleanupFailed = 'CLEANUP_FAILED';
  static const String ftpIntegrityValidationFailed =
      'FTP_INTEGRITY_VALIDATION_FAILED';
}
