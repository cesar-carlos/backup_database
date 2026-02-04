/// Serviço para gerenciar locks de download de arquivos.
/// Previne conflitos quando múltiplos clientes tentam baixar o mesmo arquivo.
abstract class IFileTransferLockService {
  /// Tenta adquirir um lock para o arquivo. Retorna `true` se o lock foi adquirido.
  /// Se o arquivo já estiver locked, retorna `false`.
  Future<bool> tryAcquireLock(String filePath);

  /// Libera o lock do arquivo.
  /// Deve ser chamado após a transferência completar (sucesso ou falha).
  Future<void> releaseLock(String filePath);

  /// Verifica se um arquivo está atualmente locked.
  Future<bool> isLocked(String filePath);

  /// Remove locks expirados (locks mantidos por muito tempo sem serem liberados).
  /// Útil para limpeza de locks "órfãos" (ex: cliente que crashou durante download).
  Future<void> cleanupExpiredLocks({Duration maxAge = const Duration(minutes: 30)});
}
