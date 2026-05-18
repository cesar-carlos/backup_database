class SocketTelemetryLimits {
  SocketTelemetryLimits._();

  static const int maxRecentMutableAudits = 100;

  static const Duration pendingRequestTtl = Duration(minutes: 5);
}

class SocketTelemetryMetrics {
  SocketTelemetryMetrics._();

  static const String errorTotalPrefix = 'socket_error_total_';

  static String requestDurationMs(String messageTypeName) =>
      'socket_request_duration_ms_$messageTypeName';

  static String errorTotal(String errorCodeName) =>
      '$errorTotalPrefix$errorCodeName';
}
