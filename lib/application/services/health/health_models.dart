import 'package:backup_database/core/errors/failure.dart';

enum HealthStatus {
  healthy,
  warning,
  critical,
}

class HealthCheckResult {
  const HealthCheckResult({
    required this.status,
    required this.timestamp,
    this.issues = const [],
    this.metrics = const {},
  });

  final HealthStatus status;
  final DateTime timestamp;
  final List<HealthIssue> issues;
  final Map<String, dynamic> metrics;

  @override
  String toString() {
    return 'HealthCheckResult(status: $status, issues: ${issues.length}, '
        'timestamp: $timestamp)';
  }
}

class HealthIssue {
  const HealthIssue({
    required this.severity,
    required this.category,
    required this.message,
    this.details,
  });

  final HealthStatus severity;
  final String category;
  final String message;
  final String? details;

  @override
  String toString() {
    return 'HealthIssue($severity: $message)';
  }
}

class HealthProbeResult {
  const HealthProbeResult(this.issues, this.metrics);

  final List<HealthIssue> issues;
  final Map<String, dynamic> metrics;
}

String healthIssueMessage(Object? failure) {
  return failureUserMessage(failure, fallback: 'Erro desconhecido');
}
