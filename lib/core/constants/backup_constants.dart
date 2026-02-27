/// Constants for backup operations.
class BackupConstants {
  BackupConstants._();

  static const int bytesInKB = 1024;
  static const int bytesInMB = 1024 * 1024;
  static const int bytesInGB = 1024 * 1024 * 1024;

  /// Minimum free disk space (bytes) required before starting a backup.
  /// Configurable margin to avoid running out of space during backup.
  static const int minFreeSpaceForBackupBytes = 500 * bytesInMB;

  /// Maximum age (days) of the last full backup for log backup preflight.
  /// If the last full is older, a warning is emitted (backup still proceeds).
  static const int maxDaysForLogBackupBaseFull = 7;
}
