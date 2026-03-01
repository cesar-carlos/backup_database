class DestinationRetryConstants {
  DestinationRetryConstants._();

  static const int maxAttempts = 3;
  static const Duration initialDelay = Duration(seconds: 2);
  static const Duration maxDelay = Duration(seconds: 30);
  static const int backoffMultiplier = 2;
  static const double jitterFactor = 0.2;
}

class StepTimeoutConstants {
  StepTimeoutConstants._();

  static const Duration ftpConnection = Duration(seconds: 15);
  static const Duration uploadFtp = Duration(minutes: 60);
  static const Duration uploadHttp = Duration(minutes: 5);
  static const Duration compression = Duration(hours: 2);
  static const Duration backupDefault = Duration(hours: 2);
  static const Duration verifyDefault = Duration(minutes: 30);
}

class CircuitBreakerConstants {
  CircuitBreakerConstants._();

  static const int failureThreshold = 3;
  static const Duration openDuration = Duration(seconds: 60);
  static const int halfOpenSuccessCount = 1;
}

class UploadParallelismConstants {
  UploadParallelismConstants._();

  static const int maxParallelUploads = 3;
}

class UploadChunkConstants {
  UploadChunkConstants._();

  static const int dropboxResumableChunkSize = 4 * 1024 * 1024;
  static const int localCopyChunkSize = 1024 * 1024;
  static const int httpUploadChunkSize = 512 * 1024;

  static const int ftpUploadBufferSize = 256 * 1024;
}
