import 'dart:convert';

import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/oauth/oauth_session_lock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration shared by the UI and headless executor in the secure store.
class OAuthConfigStore {
  OAuthConfigStore(
    this.credentials, {
    required this.storageKey,
    required this.label,
    OAuthSessionLock? sessionLock,
  }) : _sessionLock =
           sessionLock ??
           OAuthSessionLock(
             fileName:
                 'oauth-config-${sha256.convert(utf8.encode(storageKey))}.lock',
           );
  final OAuthSessionLock _sessionLock;
  final ISecureCredentialService credentials;
  final String storageKey;
  final String label;

  Future<Map<String, dynamic>?> read() => _sessionLock.run(_read);

  Future<Map<String, dynamic>?> _read() async {
    if (!(await credentials.containsKey(key: storageKey)).getOrThrow()) {
      return null;
    }
    final data = (await credentials.getToken(key: storageKey)).getOrThrow();
    if (data['removed'] == true) return null;
    _validate(data);
    return data;
  }

  Future<Map<String, dynamic>?> readForUi() => _sessionLock.run(() async {
    // A tombstone prevents other sessions from resurrecting removed config.
    if ((await credentials.containsKey(key: storageKey)).getOrThrow()) {
      return _read();
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(storageKey);
    if (legacy == null) return null;
    final data =
        jsonDecode(EncryptionService.decrypt(legacy)) as Map<String, dynamic>;
    try {
      await _write(data);
    } on Exception {
      // A failed response can follow a durable write; confirm before retrying.
      final persisted = await _read();
      if (!mapEquals(persisted, data)) rethrow;
      return persisted;
    }
    return _read();
  });

  void _validate(Map<String, dynamic> data) {
    if (data['clientId'] is! String ||
        (data['clientId'] as String).trim().isEmpty ||
        (data['clientSecret'] != null && data['clientSecret'] is! String)) {
      throw StateError(
        'Configuração OAuth $label inválida. Reconfigure o destino.',
      );
    }
  }

  Future<void> write(Map<String, dynamic> data) =>
      _sessionLock.run(() => _write(data));

  Future<void> _write(Map<String, dynamic> data) async {
    _validate(data);
    (await credentials.storeToken(
      key: storageKey,
      tokenData: data,
    )).getOrThrow();
  }

  Future<void> remove() => _sessionLock.run(() async {
    (await credentials.storeToken(
      key: storageKey,
      tokenData: {'removed': true},
    )).getOrThrow();
  });
}
