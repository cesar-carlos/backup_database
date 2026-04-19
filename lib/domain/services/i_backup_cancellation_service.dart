/// Serviço de cancelamento de backups em execução.
///
/// O orchestrator marca cada execução com uma `tag` (geralmente
/// `backup-<scheduleId>` ou `backup-<historyId>`) ao chamar o
/// `ProcessService`. Este serviço permite, da camada de aplicação ou da
/// presentation, encerrar imediatamente o processo associado a uma tag.
///
/// Implementação concreta vive em `infrastructure/` e delega para
/// `ProcessService.cancelByTag` (interna), preservando a regra de Clean
/// Architecture: nada fora de domain depende de tipos de infraestrutura.
abstract class IBackupCancellationService {
  /// Cancela o processo de backup associado a [tag], se houver um em
  /// execução. Operação idempotente — chamar duas vezes não dá erro.
  void cancelByTag(String tag);

  /// Conveniência: cancela um backup pelo identificador do schedule.
  /// Cobre o caso comum em que a UI conhece apenas o `scheduleId`.
  void cancelBySchedule(String scheduleId) =>
      cancelByTag('backup-$scheduleId');

  /// Conveniência: cancela pelo `BackupHistory.id` quando a UI conhece o
  /// histórico em curso.
  void cancelByHistoryId(String historyId) =>
      cancelByTag('backup-$historyId');

  /// Cancela TODOS os processos de backup em execução. Usado durante o
  /// shutdown da aplicação para evitar processos zumbis (`pg_basebackup`,
  /// `sqlcmd`, `dbisql`, etc.) quando o usuário fecha a janela ou o SCM
  /// para o serviço Windows. Operação best-effort.
  void cancelAllRunning();
}
