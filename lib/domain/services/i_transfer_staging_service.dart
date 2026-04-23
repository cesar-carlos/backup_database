abstract class ITransferStagingService {
  /// Copia o artefato para `remote/{pasta}/...` sob o diretório base de transferência.
  ///
  /// - Se [remoteFolderKey] for nulo, a pasta é [scheduleId] (layout legado).
  /// - Se [remoteFolderKey] for informado (ex.: `runId` em `remoteCommand`), usa essa pasta.
  Future<String?> copyToStaging(
    String backupPath,
    String scheduleId, {
    String? remoteFolderKey,
  });

  /// Remove `remote/{pasta}/` e todo o conteúdo.
  ///
  /// - Se [remoteFolderKey] for nulo, a pasta é [scheduleId] (legado).
  /// - Caso contrário, a pasta é [remoteFolderKey] (alinhada ao [copyToStaging]).
  Future<void> cleanupStaging(
    String scheduleId, {
    String? remoteFolderKey,
  });

  /// Remove pastas `remote/<chave>/` cujo arquivo mais recente no subtree
  /// excedeu [maxAge] (alinhado ao TTL de artefato remoto e ao `410`, PR-4).
  Future<void> cleanupOldBackups({Duration maxAge = const Duration(hours: 24)});
}
