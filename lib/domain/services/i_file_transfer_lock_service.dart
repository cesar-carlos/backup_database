import 'package:backup_database/domain/constants/transfer_lease.dart';

/// Serviço para gerenciar locks de download de arquivos.
/// Previne conflitos quando múltiplos clientes tentam baixar o mesmo arquivo.
///
/// PR-4: o lock é um **lease** persistido (`owner`, `runId` opcional,
/// `acquiredAt`, `expiresAt`) em JSON v1, com compat. com arquivo legado
/// (só timestamp ISO). Re-aquisição pelo mesmo `owner` ou pelo mesmo
/// `runId` renova o lease (resume / reconexão).
abstract class IFileTransferLockService {
  /// Tenta adquirir o lease. Retorna `true` se adquirido (ou renovado).
  /// Se outro ator tiver o lease ainda valido, retorna `false`.
  Future<bool> tryAcquireLock(
    String filePath, {
    String owner = 'unknown',
    String? runId,
    Duration leaseTtl = kDefaultTransferLeaseTtl,
  });

  /// Libera o lock do arquivo.
  /// Deve ser chamado após a transferência completar (sucesso ou falha).
  Future<void> releaseLock(String filePath);

  /// Verifica se um arquivo está atualmente locked.
  Future<bool> isLocked(String filePath);

  /// Remove locks expirados (locks mantidos por muito tempo sem serem liberados).
  /// Útil para limpeza de locks "órfãos" (ex: cliente que crashou durante download).
  Future<void> cleanupExpiredLocks({
    Duration maxAge = kDefaultTransferLeaseTtl,
  });
}
