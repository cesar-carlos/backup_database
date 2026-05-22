class TemporaryBackupCleanupResult {
  const TemporaryBackupCleanupResult({
    required this.deletedCount,
    required this.bytesFreed,
  });

  final int deletedCount;
  final int bytesFreed;
}

abstract class ITemporaryBackupCleanupService {
  Future<TemporaryBackupCleanupResult> cleanupOrphanedFailedUploads({
    Duration maxAge = const Duration(hours: 24),
  });
}
