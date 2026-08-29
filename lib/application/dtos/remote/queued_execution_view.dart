class QueuedExecutionView {
  const QueuedExecutionView({
    required this.runId,
    required this.scheduleId,
    required this.queuedPosition,
    required this.queuedAt,
    this.requestedBy,
  });

  final String runId;
  final String scheduleId;
  final int queuedPosition;
  final DateTime queuedAt;
  final String? requestedBy;
}
