/// Scheduler que dispara `pruneExpired()` na fila de execucao remota
/// periodicamente. Removido em `stop()` (ex.: shutdown do servidor).
///
/// Implementacao concreta vive em
/// `lib/infrastructure/socket/server/execution_queue_housekeeping_scheduler.dart`.
abstract class IExecutionQueueHousekeepingScheduler {
  /// Inicia o ciclo de housekeeping. Idempotente: chamadas repetidas
  /// sao no-op enquanto o scheduler ja estiver ativo.
  void start();

  /// Para o ciclo. Idempotente.
  void stop();
}
