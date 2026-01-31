import 'dart:convert';

import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/failure.dart';
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

class DropboxAuthProvider extends ChangeNotifier {
  DropboxAuthProvider(this._authService);
  final DropboxAuthService _authService;

  static const _oauthConfigKey = 'dropbox_oauth_config';

  bool _isLoading = false;
  bool _isInitialized = false;
  bool _isConfigured = false;
  String? _error;
  String? _currentEmail;
  DropboxOAuthConfig? _oauthConfig;

  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isConfigured => _isConfigured;
  bool get isSignedIn => _authService.isSignedIn;
  String? get error => _error;
  String? get currentEmail => _currentEmail ?? _authService.currentUserEmail;
  DropboxOAuthConfig? get oauthConfig => _oauthConfig;

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
          },
          (_) {
            // Nenhuma sessão ativa
          },
        );
      }

      _isInitialized = true;
      _isLoading = false;
    } on Object catch (e) {
      _error = 'Erro ao inicializar: $e';
      _isLoading = false;
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
      _isLoading = false;
      notifyListeners();

      return true;
    } on Object catch (e) {
      _error = 'Erro ao configurar OAuth: $e';
      _isLoading = false;
      notifyListeners();
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

    try {
      await windowManager.setPreventClose(true);
    } on Object catch (e) {
      LoggerService.debug('Window manager setPreventClose: $e');
    }

    try {
      final result = await _authService.signIn();

      return result.fold(
        (authResult) {
          _currentEmail = authResult.email;
          _isLoading = false;
          notifyListeners();
          return true;
        },
        (exception) {
          _error = exception is Failure
              ? exception.message
              : exception.toString();
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );
    } finally {
      try {
        await windowManager.setPreventClose(false);
      } on Object catch (e) {
        LoggerService.debug('Window manager setPreventClose: $e');
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

      return true;
    } on Object catch (e) {
      _error = 'Erro ao remover configuração: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
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
    } on Object catch (e) {
      LoggerService.debug('Erro ao carregar config OAuth Dropbox: $e');
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
      rethrow;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
