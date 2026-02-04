/// Constants for scheduler operations.
class SchedulerConstants {
  SchedulerConstants._();

  // Check intervals
  static const Duration scheduleCheckInterval = Duration(minutes: 1);
  static const Duration backupWaitCheckInterval = Duration(seconds: 2);

  // Progress values
  static const double backupCompleteProgress = 0.85;
  static const double uploadProgressBase = 0.85;
  static const double uploadProgressRange = 0.10;
  static const double uploadStepProgress = 0.1;
  static const double compressionStartProgress = 0.5;
  static const double compressionRunningProgress = 0.6;
  static const double compressionCompleteProgress = 0.8;

  // Timeouts
  static const Duration defaultBackupWaitTimeout = Duration(minutes: 5);

  // Logging intervals
  static const int progressLogIntervalSeconds = 10;
}
