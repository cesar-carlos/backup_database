class RunDiagnosticsLogsView {
  const RunDiagnosticsLogsView({
    required this.runId,
    required this.lines,
    required this.truncated,
    required this.totalLines,
  });

  final String runId;
  final List<String> lines;
  final bool truncated;
  final int totalLines;

  bool get isEmpty => lines.isEmpty;
}

class RunDiagnosticsErrorView {
  const RunDiagnosticsErrorView({
    required this.runId,
    required this.found,
    this.errorMessage,
    this.errorCode,
    this.errorCodeMessage,
    this.stackTrace,
    this.context,
  });

  final String runId;
  final bool found;
  final String? errorMessage;
  final String? errorCode;
  final String? errorCodeMessage;
  final String? stackTrace;
  final Map<String, dynamic>? context;
}

class RunDiagnosticsView {
  const RunDiagnosticsView({
    this.logs,
    this.logsError,
    this.errorDetails,
    this.errorDetailsError,
  });

  final RunDiagnosticsLogsView? logs;
  final String? logsError;
  final RunDiagnosticsErrorView? errorDetails;
  final String? errorDetailsError;

  bool get hasContent => logs != null || errorDetails != null;
}
