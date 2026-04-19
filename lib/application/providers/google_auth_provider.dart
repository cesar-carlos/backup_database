import 'dart:convert';

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class GoogleOAuthConfig {
  const GoogleOAuthConfig({
    required this.clientId,
    this.clientSecret,
  });

  factory GoogleOAuthConfig.fromJson(Map<String, dynamic> json) {
    return GoogleOAuthConfig(
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

class GoogleAuthProvider extends ChangeNotifier with AsyncStateMixin {
  GoogleAuthProvider(this._authService);
  final GoogleAuthService _authService;

  static const _oauthConfigKey = 'google_oauth_config';

  bool _isInitialized = false;
  bool _isConfigured = false;
  String? _currentEmail;
  GoogleOAuthConfig? _oauthConfig;
  Future<void>? _initializeFuture;

  bool get isInitialized => _isInitialized;
  bool get isConfigured => _isConfigured;
  bool get isSignedIn => _authService.isSignedIn;
  String? get currentEmail => _currentEmail ?? _authService.currentUserEmail;
  GoogleOAuthConfig? get oauthConfig => _oauthConfig;

  Future<void> initialize() async {
    if (_isInitialized) return;
    // Reentrância segura: chamadas concorrentes durante boot recebem o
    // mesmo Future em curso, evitando dupla inicialização.
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
            (authResult) {
              _currentEmail = authResult.email;
              LoggerService.info('Sessão Google restaurada: $_currentEmail');
            },
            (_) {
              LoggerService.debug('Nenhuma sessão Google ativa');
            },
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
        _oauthConfig = GoogleOAuthConfig(
          clientId: clientId,
          clientSecret: clientSecret,
        );

        await _saveOAuthConfig();

        await _authService.initialize(
          clientId: clientId,
          clientSecret: clientSecret,
        );

        _isConfigured = true;
        LoggerService.info('Configuração OAuth Google salva');
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

    // Proteger contra fechamento durante a autenticação OAuth.
    // O webview pode causar eventos de fechamento inesperados.
    try {
      await windowManager.setPreventClose(true);
      LoggerService.debug('Proteção contra fechamento ativada para OAuth');
    } on Object catch (e) {
      LoggerService.warning('Erro ao ativar proteção contra fechamento: $e');
    }

    try {
      final ok = await runAsync<bool>(
        action: () async {
          final result = await _authService.signIn();
          return result.fold(
            (authResult) {
              _currentEmail = authResult.email;
              LoggerService.info('Login Google realizado: $_currentEmail');
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
        LoggerService.debug('Proteção contra fechamento desativada');
      } on Object catch (e) {
        LoggerService.warning(
          'Erro ao desativar proteção contra fechamento: $e',
        );
      }
    }
  }

  Future<void> signOut() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao fazer logout',
      action: () async {
        await _authService.signOut();
        _currentEmail = null;
        LoggerService.info('Logout Google realizado');
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
        LoggerService.info('Configuração OAuth Google removida');
        return true;
      },
    );
    return ok ?? false;
  }

  GoogleAuthResult? getAuthResult() {
    if (!_authService.isSignedIn) return null;

    return GoogleAuthResult(
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
      _oauthConfig = GoogleOAuthConfig.fromJson(json);

      LoggerService.debug('Configuração OAuth carregada');
    } on Object catch (e, s) {
      // Sem fail silencioso: registra erro e expõe para a UI para que o
      // operador saiba que precisa reconfigurar credenciais OAuth.
      setErrorManual(
        'Configuração OAuth corrompida ou inválida. Reconfigure as credenciais.',
      );
      LoggerService.error('Erro ao carregar configuração OAuth Google', e, s);
    }
  }

  Future<void> _saveOAuthConfig() async {
    if (_oauthConfig == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_oauthConfig!.toJson());
      final encryptedConfig = EncryptionService.encrypt(json);
      await prefs.setString(_oauthConfigKey, encryptedConfig);
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configuração OAuth', e);
      rethrow;
    }
  }
}
