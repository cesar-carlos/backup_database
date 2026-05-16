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

  Future<String> readPasswordOrEmpty(String key) async {
    final passwordResult = await _service.getPassword(key: key);
    return passwordResult.getOrElse((_) => '');
  }

  Future<void> deletePassword(String key) async {
    await _service.deletePassword(key: key);
  }
}
