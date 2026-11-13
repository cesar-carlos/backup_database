import 'dart:convert';

import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration shared by the UI and headless executor in the secure store.
class OAuthConfigStore {
  OAuthConfigStore(
    this.credentials, {
    required this.storageKey,
    required this.label,
  });
  final ISecureCredentialService credentials;
  final String storageKey;
  final String label;

  Future<Map<String, dynamic>?> read() async {
    if (!(await credentials.containsKey(key: storageKey)).getOrThrow()) {
      return null;
    }
    final data = (await credentials.getToken(key: storageKey)).getOrThrow();
    if (data['removed'] == true) return null;
    _validate(data);
    return data;
  }

  Future<Map<String, dynamic>?> readForUi() async {
    // A tombstone prevents other sessions from resurrecting removed config.
    if ((await credentials.containsKey(key: storageKey)).getOrThrow()) {
      return read();
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(storageKey);
    if (legacy == null) return null;
    final data =
        jsonDecode(EncryptionService.decrypt(legacy)) as Map<String, dynamic>;
    await write(data);
    return read();
  }

  void _validate(Map<String, dynamic> data) {
    if (data['clientId'] is! String ||
        (data['clientId'] as String).trim().isEmpty ||
        (data['clientSecret'] != null && data['clientSecret'] is! String)) {
      throw StateError(
        'Configuração OAuth $label inválida. Reconfigure o destino.',
      );
    }
  }

  Future<void> write(Map<String, dynamic> data) async {
    _validate(data);
    (await credentials.storeToken(
      key: storageKey,
      tokenData: data,
    )).getOrThrow();
  }

  Future<void> remove() async {
    (await credentials.storeToken(
      key: storageKey,
      tokenData: {'removed': true},
    )).getOrThrow();
  }
}
