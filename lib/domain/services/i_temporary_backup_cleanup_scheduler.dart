abstract class ITemporaryBackupCleanupScheduler {
  void start({Duration interval = const Duration(hours: 1)});

  void stop();
}
