/// Scheduler de retencao do audit log de comandos mutaveis (PR-6).
///
/// Implementacao concreta vive em
/// `lib/infrastructure/socket/server/audit_retention_scheduler.dart`.
abstract class IAuditRetentionScheduler {
  void start();
  void stop();
}
