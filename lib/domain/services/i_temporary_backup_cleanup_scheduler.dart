abstract class ITemporaryBackupCleanupScheduler {
  bool get isRunning;
  void start({Duration interval = const Duration(hours: 1)});

  void stop();
}
