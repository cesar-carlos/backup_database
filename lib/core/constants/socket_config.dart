class SocketConfig {
  SocketConfig._();

  static const int defaultPort = 9527;
  static const int chunkSize = 131072; // 128KB
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration heartbeatTimeout = Duration(seconds: 60);
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration scheduleRequestTimeout = Duration(seconds: 15);
  static const Duration fileTransferTimeout = Duration(minutes: 5);
  static const Duration backupExecutionTimeout = Duration(minutes: 10);
  static const int maxRetries = 3;
  static const int maxReconnectAttempts = 5;

  // Retry configuration for downloads
  static const Duration downloadRetryInitialDelay = Duration(seconds: 2);
  static const Duration downloadRetryMaxDelay = Duration(seconds: 30);
  static const int downloadRetryBackoffMultiplier = 2;
}
