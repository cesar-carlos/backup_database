class LogStepConstants {
  LogStepConstants._();

  static const String backupStarted = 'backup_started';
  static const String backupDbDone = 'backup_db_done';
  static const String compressionStarted = 'compression_started';
  static const String compressionDone = 'compression_done';
  static const String compressionSkipped = 'compression_skipped';
  static const String compressionFailed = 'compression_failed';
  static const String scriptPostBackup = 'script_post_backup';
  static const String backupSuccess = 'backup_success';
  static const String backupError = 'backup_error';
  static const String backupFileNotFound = 'backup_file_not_found';
  static const String backupCancelled = 'backup_cancelled';
  static const String uploadFailed = 'upload_failed';

  static String cleanupError(String destinationId) =>
      'cleanup_error_$destinationId';
}
