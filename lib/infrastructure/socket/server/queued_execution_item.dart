/// Item enfileirado na fila de execucoes remotas. Mantem metadados para
/// quando o item for dequeueado (backup continua correlacionavel por
/// [runId] mesmo apos reconexoes).
class QueuedExecutionItem {
  QueuedExecutionItem({
    required this.runId,
    required this.scheduleId,
    required this.clientId,
    required this.requestId,
    required this.requestedBy,
    required this.queuedAt,
  });

  final String runId;
  final String scheduleId;
  final String clientId;
  final int requestId;
  final String requestedBy;
  final DateTime queuedAt;
}
