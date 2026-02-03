abstract class ITransferStagingService {
  Future<String?> copyToStaging(String backupPath, String scheduleId);

  /// Remove o arquivo de staging para um schedule específico.
  /// Deve ser chamado após o cliente confirmar o recebimento do arquivo.
  Future<void> cleanupStaging(String scheduleId);

  /// Remove todos os arquivos de staging mais antigos que [maxAge].
  /// Útil para limpeza periódica de arquivos órfãos (ex: downloads incompletos).
  Future<void> cleanupOldBackups({Duration maxAge = const Duration(days: 7)});
}
