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
    this.expiresAt,
  });

  final String runId;
  final String scheduleId;
  final String clientId;
  final int requestId;
  final String requestedBy;
  final DateTime queuedAt;

  /// PR-6: TTL — item nao drenado ate este momento sera removido pelo
  /// `pruneExpired` da `ExecutionQueueService` e publicado como
  /// `backupDequeued(reason: 'ttlExpired')`. `null` mantem compat com
  /// itens persistidos pre-PR-6 (sem TTL — never expires).
  final DateTime? expiresAt;

  /// `true` quando [expiresAt] foi atingido. Itens sem `expiresAt`
  /// nunca expiram.
  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !now.isBefore(expiresAt!);
}
