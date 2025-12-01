import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/encryption/encryption_service.dart';
import '../../core/errors/failure.dart';
import '../../core/utils/logger_service.dart';
import '../../infrastructure/external/google/google_auth_service.dart';

class GoogleOAuthConfig {
  final String clientId;
  final String? clientSecret;

  const GoogleOAuthConfig({
    required this.clientId,
    this.clientSecret,
  });

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'clientSecret': clientSecret,
      };

  factory GoogleOAuthConfig.fromJson(Map<String, dynamic> json) {
    return GoogleOAuthConfig(
      clientId: json['clientId'] as String,
      clientSecret: json['clientSecret'] as String?,
    );
  }
}

class GoogleAuthProvider extends ChangeNotifier {
  final GoogleAuthService _authService;

  static const _oauthConfigKey = 'google_oauth_config';

  GoogleAuthProvider(this._authService);

  bool _isLoading = false;
  bool _isInitialized = false;
  bool _isConfigured = false;
  String? _error;
  String? _currentEmail;
  GoogleOAuthConfig? _oauthConfig;

  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isConfigured => _isConfigured;
  bool get isSignedIn => _authService.isSignedIn;
  String? get error => _error;
  String? get currentEmail => _currentEmail ?? _authService.currentUserEmail;
  GoogleOAuthConfig? get oauthConfig => _oauthConfig;

  Future<void> initialize() async {
    if (_isInitialized) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
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
      _isLoading = false;
    } catch (e) {
      _error = 'Erro ao inicializar: $e';
      _isLoading = false;
      LoggerService.error('Erro ao inicializar GoogleAuthProvider', e);
    }

    notifyListeners();
  }

  Future<bool> configureOAuth({
    required String clientId,
    String? clientSecret,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
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
      _isLoading = false;
      notifyListeners();

      LoggerService.info('Configuração OAuth Google salva');
      return true;
    } catch (e) {
      _error = 'Erro ao configurar OAuth: $e';
      _isLoading = false;
      notifyListeners();
      LoggerService.error('Erro ao configurar OAuth', e);
      return false;
    }
  }

  Future<bool> signIn() async {
    if (!_isConfigured) {
      _error = 'Configure as credenciais OAuth primeiro.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    // Proteger contra fechamento durante a autenticação OAuth
    // O webview pode causar eventos de fechamento inesperados
    try {
      await windowManager.setPreventClose(true);
      LoggerService.debug('Proteção contra fechamento ativada para OAuth');
    } catch (e) {
      LoggerService.warning('Erro ao ativar proteção contra fechamento: $e');
    }

    try {
      final result = await _authService.signIn();

      return result.fold(
        (authResult) {
          _currentEmail = authResult.email;
          _isLoading = false;
          notifyListeners();
          LoggerService.info('Login Google realizado: $_currentEmail');
          return true;
        },
        (exception) {
          _error = exception is Failure ? exception.message : exception.toString();
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );
    } finally {
      // Restaurar comportamento normal de fechamento
      try {
        await windowManager.setPreventClose(false);
        LoggerService.debug('Proteção contra fechamento desativada');
      } catch (e) {
        LoggerService.warning('Erro ao desativar proteção contra fechamento: $e');
      }
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    await _authService.signOut();

    _currentEmail = null;
    _isLoading = false;
    notifyListeners();

    LoggerService.info('Logout Google realizado');
  }

  Future<bool> removeOAuthConfig() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.signOut();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_oauthConfigKey);

      _oauthConfig = null;
      _isConfigured = false;
      _currentEmail = null;
      _isLoading = false;
      notifyListeners();

      LoggerService.info('Configuração OAuth Google removida');
      return true;
    } catch (e) {
      _error = 'Erro ao remover configuração: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  GoogleAuthResult? getAuthResult() {
    if (!_authService.isSignedIn) return null;

    return GoogleAuthResult(
      accessToken: _authService.accessToken!,
      refreshToken: null,
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
    } catch (e) {
      LoggerService.warning('Erro ao carregar configuração OAuth: $e');
    }
  }

  Future<void> _saveOAuthConfig() async {
    if (_oauthConfig == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_oauthConfig!.toJson());
      final encryptedConfig = EncryptionService.encrypt(json);
      await prefs.setString(_oauthConfigKey, encryptedConfig);
    } catch (e) {
      LoggerService.error('Erro ao salvar configuração OAuth', e);
      rethrow;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

