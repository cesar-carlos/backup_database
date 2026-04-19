/// Constants for backup operations.
class BackupConstants {
  BackupConstants._();

  static const int bytesInKB = 1024;
  static const int bytesInMB = 1024 * 1024;
  static const int bytesInGB = 1024 * 1024 * 1024;

  /// Minimum free disk space (bytes) required before starting a backup.
  /// Used como fallback quando não conseguimos estimar o tamanho real
  /// do banco. Configurable margin to avoid running out of space during
  /// backup.
  static const int minFreeSpaceForBackupBytes = 500 * bytesInMB;

  /// Multiplicador aplicado ao tamanho real do banco (quando conhecido)
  /// para reservar espaço para arquivos temporários, compressão e
  /// crescimento durante o backup. Ex.: 2.0 = 2× o tamanho do banco.
  static const double backupSpaceSafetyFactor = 2;

  /// Maximum age (days) of the last full backup for log backup preflight.
  /// If the last full is older, a warning is emitted (backup still proceeds).
  static const int maxDaysForLogBackupBaseFull = 7;

  /// Running history rows older than this are closed as error when the
  /// scheduler starts (recovery after crash or kill).
  static const Duration staleRunningBackupMaxAge = Duration(hours: 24);
}
