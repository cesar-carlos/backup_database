import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';

class SecureCredentialHelper {
  SecureCredentialHelper(this._service);

  final ISecureCredentialService _service;

  Future<void> storePasswordOrThrow({
    required String key,
    required String password,
  }) async {
    final storeResult = await _service.storePassword(
      key: key,
      password: password,
    );
    if (storeResult.isError()) {
      throw storeResult.exceptionOrNull()!;
    }
  }

  /// Lê a senha do vault.
  ///
  /// Retorna a senha quando OK. Retorna `''` quando:
  /// - O vault não tem entrada para `key` (caso esperado em config sem
  ///   senha persistida).
  /// - **OU** a leitura do vault falhou (I/O / permissão / vault
  ///   corrompido). Nesse caso emitimos um warning para que o usuário
  ///   tenha como diagnosticar (antes esse caminho era silencioso e
  ///   indistinguível de "config sem senha").
  Future<String> readPasswordOrEmpty(String key) async {
    final passwordResult = await _service.getPassword(key: key);
    return passwordResult.fold(
      (password) => password,
      (failure) {
        LoggerService.warning(
          'Falha ao ler credencial do vault (key=$key); '
          'tratando como senha vazia: $failure',
        );
        return '';
      },
    );
  }

  /// Remove a senha do vault.
  ///
  /// Loga warning se a remoção falhar (antes era silenciosa) — sem
  /// isso, falhas no vault deixavam o segredo orfão na keychain após
  /// `delete` no repositório, levando a split-brain entre Drift e o
  /// vault.
  Future<void> deletePassword(String key) async {
    final result = await _service.deletePassword(key: key);
    if (result.isError()) {
      LoggerService.warning(
        'Falha ao remover credencial do vault (key=$key): '
        '${result.exceptionOrNull()}. A linha do SGBD pode ter sido '
        'deletada mas o segredo permanece no keychain.',
      );
    }
  }
}
