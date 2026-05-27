/// Constants for backup operations.
class BackupConstants {
  BackupConstants._();

  static const int bytesInKB = 1024;
  static const int bytesInMB = 1024 * 1024;
  static const int bytesInGB = 1024 * 1024 * 1024;

  /// Minimum free disk space (bytes) required before starting a backup.
  /// Used como fallback quando não conseguimos estimar o tamanho real
  /// do banco. Configurable margin to avoid running out of space during
  /// backup.
  static const int minFreeSpaceForBackupBytes = 500 * bytesInMB;

  /// Multiplicador aplicado ao tamanho real do banco (quando conhecido)
  /// para reservar espaço para arquivos temporários, compressão e
  /// crescimento durante o backup. Ex.: 2.0 = 2× o tamanho do banco.
  static const double backupSpaceSafetyFactor = 2;

  /// Maximum age (days) of the last full backup for log backup preflight.
  /// If the last full is older, a warning is emitted (backup still proceeds).
  static const int maxDaysForLogBackupBaseFull = 7;

  /// Running history rows older than this are closed as error when the
  /// scheduler starts (recovery after crash or kill).
  static const Duration staleRunningBackupMaxAge = Duration(hours: 24);

  /// Limite de execucoes concorrentes de backup no servidor.
  ///
  /// Ratificado em PR-6 como permanente para `v1` da API remota (ver
  /// `docs/notes/execucao_remota_backlog_2026-05-27.md` — secao "Itens fora
  /// do escopo"). Mudar este valor exige ADR + revisao da fila e do mutex
  /// em `SchedulerService`.
  static const int maxConcurrentBackups = 1;

  /// Watchdog: tempo maximo sem `backupProgress` antes do scheduler
  /// considerar o backup travado e disparar `cancelExecution`.
  ///
  /// Deve ser maior que o intervalo natural entre `backupProgress` events
  /// do orchestrator. PR-6 valida empiricamente em backups grandes.
  static const Duration runningHeartbeatTimeout = Duration(minutes: 10);

  /// Hard limit: duracao maxima absoluta de um backup. Ultrapassado, o
  /// scheduler dispara `cancelExecution` com `errorCode = RUN_HARD_TIMEOUT`.
  static const Duration runningMaxDuration = Duration(hours: 6);

  /// Intervalo do timer de watchdog (separado do `_checkTimer` de
  /// agendamento). Deve ser <= `runningHeartbeatTimeout / 2`.
  static const Duration watchdogCheckInterval = Duration(minutes: 1);

  /// TTL de item enfileirado na fila de execucao remota. Itens nao
  /// drenados nesse periodo viram `cancelled` com `QUEUED_TTL_EXPIRED`.
  static const Duration queuedItemTtl = Duration(minutes: 30);

  /// Intervalo do housekeeping da fila (limpa itens expirados).
  static const Duration queueHousekeepingInterval = Duration(minutes: 1);

  /// Periodo de retencao do audit log estruturado (`MutableCommandAudit`).
  /// Apos esse periodo o job de retencao apaga entradas antigas.
  static const Duration auditRetentionPeriod = Duration(days: 30);
}
