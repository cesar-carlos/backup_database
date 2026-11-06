abstract class IRemoteStagingCleanupScheduler {
  bool get isRunning;
  void start();
  void stop();
}
