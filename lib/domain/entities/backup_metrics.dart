class BackupMetrics {
  const BackupMetrics({
    required this.totalDuration,
    required this.backupDuration,
    required this.verifyDuration,
    required this.backupSizeBytes,
    required this.backupSpeedMbPerSec,
    required this.backupType,
    required this.flags,
  });

  final Duration totalDuration;
  final Duration backupDuration;
  final Duration verifyDuration;
  final int backupSizeBytes;
  final double backupSpeedMbPerSec;
  final String backupType;
  final BackupFlags flags;

  String get backupSizeFormatted => _formatBytes(backupSizeBytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class BackupFlags {
  const BackupFlags({
    required this.compression,
    required this.verifyPolicy,
    required this.stripingCount,
    required this.withChecksum,
    required this.stopOnError,
  });

  final bool compression;
  final String verifyPolicy;
  final int stripingCount;
  final bool withChecksum;
  final bool stopOnError;
}
