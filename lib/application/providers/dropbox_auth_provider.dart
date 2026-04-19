import 'dart:convert';

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class DropboxOAuthConfig {
  const DropboxOAuthConfig({required this.clientId, this.clientSecret});

  factory DropboxOAuthConfig.fromJson(Map<String, dynamic> json) {
    return DropboxOAuthConfig(
      clientId: json['clientId'] as String,
      clientSecret: json['clientSecret'] as String?,
    );
  }
  final String clientId;
  final String? clientSecret;

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'clientSecret': clientSecret,
  };
}

class DropboxAuthProvider extends ChangeNotifier with AsyncStateMixin {
  DropboxAuthProvider(this._authService);
  final DropboxAuthService _authService;

  static const _oauthConfigKey = 'dropbox_oauth_config';

  bool _isInitialized = false;
  bool _isConfigured = false;
  String? _currentEmail;
  DropboxOAuthConfig? _oauthConfig;
  Future<void>? _initializeFuture;

  bool get isInitialized => _isInitialized;
  bool get isConfigured => _isConfigured;
  bool get isSignedIn => _authService.isSignedIn;
  String? get currentEmail => _currentEmail ?? _authService.currentUserEmail;
  DropboxOAuthConfig? get oauthConfig => _oauthConfig;

  Future<void> initialize() async {
    if (_isInitialized) return;
    final inFlight = _initializeFuture;
    if (inFlight != null) return inFlight;
    return _initializeFuture = _doInitialize().whenComplete(() {
      _initializeFuture = null;
    });
  }

  Future<void> _doInitialize() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao inicializar',
      action: () async {
        await _loadOAuthConfig();

        if (_oauthConfig != null) {
          await _authService.initialize(
            clientId: _oauthConfig!.clientId,
            clientSecret: _oauthConfig!.clientSecret,
          );
          _isConfigured = true;

          final silentResult = await _authService.signInSilently();
          silentResult.fold(
            (authResult) => _currentEmail = authResult.email,
            (_) {},
          );
        }

        _isInitialized = true;
      },
    );
  }

  Future<bool> configureOAuth({
    required String clientId,
    String? clientSecret,
  }) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao configurar OAuth',
      action: () async {
        _oauthConfig = DropboxOAuthConfig(
          clientId: clientId,
          clientSecret: clientSecret,
        );

        await _saveOAuthConfig();

        await _authService.initialize(
          clientId: clientId,
          clientSecret: clientSecret,
        );

        _isConfigured = true;
        return true;
      },
    );
    return ok ?? false;
  }

  Future<bool> signIn() async {
    if (!_isConfigured) {
      setErrorManual('Configure as credenciais OAuth primeiro.');
      return false;
    }

    try {
      await windowManager.setPreventClose(true);
    } on Object catch (e) {
      LoggerService.debug('Window manager setPreventClose: $e');
    }

    try {
      final ok = await runAsync<bool>(
        action: () async {
          final result = await _authService.signIn();
          return result.fold(
            (authResult) {
              _currentEmail = authResult.email;
              return true;
            },
            (exception) => throw exception,
          );
        },
      );
      return ok ?? false;
    } finally {
      try {
        await windowManager.setPreventClose(false);
      } on Object catch (e) {
        LoggerService.debug('Window manager setPreventClose: $e');
      }
    }
  }

  Future<void> signOut() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao fazer logout',
      action: () async {
        await _authService.signOut();
        _currentEmail = null;
      },
    );
  }

  Future<bool> removeOAuthConfig() async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao remover configuração',
      action: () async {
        await _authService.signOut();

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_oauthConfigKey);

        _oauthConfig = null;
        _isConfigured = false;
        _currentEmail = null;
        return true;
      },
    );
    return ok ?? false;
  }

  DropboxAuthResult? getAuthResult() {
    if (!_authService.isSignedIn) return null;

    return DropboxAuthResult(
      accessToken: _authService.accessToken!,
      email: _authService.currentUserEmail!,
    );
  }

  Future<void> _loadOAuthConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encryptedConfig = prefs.getString(_oauthConfigKey);

      if (encryptedConfig == null) return;

      final decryptedConfig = EncryptionService.decrypt(encryptedConfig);
      final json = jsonDecode(decryptedConfig) as Map<String, dynamic>;
      _oauthConfig = DropboxOAuthConfig.fromJson(json);
    } on Object catch (e, s) {
      // Não propagamos como exception para não quebrar a inicialização —
      // apenas marcamos o erro e seguimos sem credenciais.
      setErrorManual(
        'Configuração OAuth corrompida ou inválida. Reconfigure as credenciais.',
      );
      LoggerService.error('Erro ao carregar config OAuth Dropbox', e, s);
    }
  }

  Future<void> _saveOAuthConfig() async {
    if (_oauthConfig == null) return;

    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_oauthConfig!.toJson());
    final encryptedConfig = EncryptionService.encrypt(json);
    await prefs.setString(_oauthConfigKey, encryptedConfig);
  }
}
