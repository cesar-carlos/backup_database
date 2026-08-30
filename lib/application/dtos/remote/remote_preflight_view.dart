enum RemotePreflightSeverity { blocking, warning, info }

enum RemotePreflightStatus { passed, passedWithWarnings, blocked }

class RemotePreflightCheckView {
  const RemotePreflightCheckView({
    required this.name,
    required this.passed,
    required this.severity,
    required this.message,
  });

  final String name;
  final bool passed;
  final RemotePreflightSeverity severity;
  final String message;
}

class RemotePreflightView {
  const RemotePreflightView({
    required this.status,
    required this.checks,
    required this.serverTimeUtc,
    this.message,
  });

  final RemotePreflightStatus status;
  final List<RemotePreflightCheckView> checks;
  final DateTime serverTimeUtc;
  final String? message;

  bool get isOk =>
      status == RemotePreflightStatus.passed ||
      status == RemotePreflightStatus.passedWithWarnings;

  bool get isBlocked => status == RemotePreflightStatus.blocked;

  bool get hasWarnings => status == RemotePreflightStatus.passedWithWarnings;
}
