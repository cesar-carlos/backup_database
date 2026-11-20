import 'dart:async';
import 'dart:convert';

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/window_close_guard.dart';
import 'package:flutter/foundation.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:shared_preferences/shared_preferences.dart';

/// Callback que inicializa o auth service concreto (Google/Dropbox).
typedef OAuthInitializeCallback = Future<void> Function({
  required String clientId,
  String? clientSecret,
});

/// Callback que dispara o fluxo de login interativo do auth service.
typedef OAuthSignInCallback<TAuthResult extends Object> =
    Future<rd.Result<TAuthResult>> Function();

/// Callback de logout do auth service.
typedef OAuthSignOutCallback = Future<void> Function();

/// Base abstrata para providers OAuth de destinos cloud
/// (`GoogleAuthProvider`, `DropboxAuthProvider`).
///
/// Antes os dois providers tinham ~200 linhas idênticas em estrutura
/// (`initialize`/`configureOAuth`/`signIn` com `windowManager.setPreventClose`/
/// `signOut`/`removeOAuthConfig`/`_loadOAuthConfig`/`_saveOAuthConfig`).
/// Esta classe centraliza esse pipeline e deixa cada provider concreto
/// implementar apenas:
///
/// - como serializar/desserializar a `TConfig` (`configToJson`,
///   `configFromJson`, `buildConfig`);
/// - como extrair `email` do `TAuthResult` (`emailOf`);
/// - como acessar `isSignedIn`/`currentUserEmail`/`accessToken` no
///   auth service concreto (getters abstratos).
///
/// As operações do auth service são injetadas via callbacks no
/// construtor — assim não precisamos de uma interface comum em
/// `domain/services` só para servir 2 implementações concretas.
abstract class OAuthProviderBase<TConfig, TAuthResult extends Object>
    extends ChangeNotifier
    with AsyncStateMixin {
  OAuthProviderBase({
    required this.oauthConfigPrefsKey,
    required this.serviceLabel,
    required this._initializeService,
    required this._signInService,
    required this._signInSilentlyService,
    required this._signOutService,
  });

  /// Chave usada em `SharedPreferences` para persistir a config OAuth.
  final String oauthConfigPrefsKey;

  /// Rótulo curto para mensagens de log (`'Google'`, `'Dropbox'`).
  final String serviceLabel;

  final OAuthInitializeCallback _initializeService;
  final OAuthSignInCallback<TAuthResult> _signInService;
  final OAuthSignInCallback<TAuthResult> _signInSilentlyService;
  final OAuthSignOutCallback _signOutService;

  bool _isInitialized = false;
  bool _isConfigured = false;
  String? _currentEmail;
  TConfig? _oauthConfig;
  Future<void>? _initializeFuture;
  Future<void> _configurationTail = Future<void>.value();
  int _configurationOperations = 0;
  int _sessionRevision = 0;
  bool _loginPending = false;

  Future<T> _serializeConfiguration<T>(Future<T> Function() action) {
    _configurationOperations++;
    final result = _configurationTail.then((_) => action()).whenComplete(() {
      _configurationOperations--;
    });
    _configurationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  bool get isInitialized => _isInitialized;
  bool get isConfigured => _isConfigured;
  String? get currentEmail =>
      isSignedIn ? currentUserEmailFromService ?? _currentEmail : null;
  TConfig? get oauthConfig => _oauthConfig;

  // ===========================================================================
  // Hooks abstratos (cada provider concreto implementa)
  // ===========================================================================

  /// Verdadeiro se o auth service concreto tem sessão ativa.
  bool get isSignedIn;

  /// Email do usuário corrente no auth service (sem cache local).
  String? get currentUserEmailFromService;

  /// Access token corrente no auth service (sem cache local).
  String? get accessTokenFromService;

  /// Constrói uma `TConfig` a partir dos campos crus (chamado por
  /// `configureOAuth`).
  TConfig buildConfig({required String clientId, String? clientSecret});

  /// Serializa a `TConfig` para o formato persistido em prefs.
  Map<String, dynamic> configToJson(TConfig config);

  /// Desserializa a `TConfig` do formato persistido em prefs.
  TConfig configFromJson(Map<String, dynamic> json);

  Future<Map<String, dynamic>?> loadPersistedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = prefs.getString(oauthConfigPrefsKey);
    return encrypted == null
        ? null
        : jsonDecode(EncryptionService.decrypt(encrypted))
              as Map<String, dynamic>;
  }

  Future<void> savePersistedConfig(Map<String, dynamic> config) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      oauthConfigPrefsKey,
      EncryptionService.encrypt(jsonEncode(config)),
    )) {
      throw StateError('Falha ao salvar configuração OAuth.');
    }
  }

  Future<void> removePersistedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(oauthConfigPrefsKey)) {
      throw StateError('Falha ao remover configuração OAuth.');
    }
  }

  /// Extrai o email do `TAuthResult` retornado pelo auth service após
  /// signIn/signInSilently.
  String emailOf(TAuthResult result);

  /// Acessores derivados (usados apenas pelos providers concretos para
  /// expor `clientId`/`clientSecret` separadamente).
  String clientIdOf(TConfig config);
  String? clientSecretOf(TConfig config);

  // ===========================================================================
  // Pipeline compartilhado
  // ===========================================================================

  /// Reentrância segura: chamadas concorrentes durante boot recebem o
  /// mesmo Future em curso, evitando dupla inicialização.
  Future<void> initialize() async {
    if (_isInitialized) return;
    final inFlight = _initializeFuture;
    if (inFlight != null) return inFlight;
    return _initializeFuture = _serializeConfiguration(_doInitialize)
        .whenComplete(() {
          _initializeFuture = null;
        });
  }

  Future<void> _doInitialize() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao inicializar',
      action: () async {
        _isConfigured = false;
        _currentEmail = null;
        await _loadOAuthConfig();
        final config = _oauthConfig;
        if (config != null) {
          await _initializeService(
            clientId: clientIdOf(config),
            clientSecret: clientSecretOf(config),
          );
          _isConfigured = true;

          final silentResult = await _signInSilentlyService();
          silentResult.fold(
            (authResult) {
              _currentEmail = emailOf(authResult);
              LoggerService.info(
                'Sessão $serviceLabel restaurada: $_currentEmail',
              );
            },
            (_) {
              LoggerService.debug('Nenhuma sessão $serviceLabel ativa');
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
  }) {
    _sessionRevision++;
    return _serializeConfiguration(
      () => _configureOAuth(clientId: clientId, clientSecret: clientSecret),
    );
  }

  Future<bool> _configureOAuth({
    required String clientId,
    String? clientSecret,
  }) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao configurar OAuth',
      action: () async {
        final config = buildConfig(
          clientId: clientId,
          clientSecret: clientSecret,
        );
        await _saveOAuthConfig(config);
        _oauthConfig = config;
        _isConfigured = false;
        _isInitialized = false;
        _currentEmail = null;
        await _initializeService(
          clientId: clientId,
          clientSecret: clientSecret,
        );
        _isConfigured = true;
        _isInitialized = true;
        LoggerService.info('Configuração OAuth $serviceLabel salva');
        return true;
      },
    );
    return ok ?? false;
  }

  /// Login interativo. Protege a janela contra fechamento durante o
  /// fluxo OAuth (o webview pode disparar `windowClose` inesperados).
  Future<bool> signIn() async {
    if (_loginPending || _configurationOperations > 0) return false;
    if (!_isConfigured) {
      setErrorManual('Configure as credenciais OAuth primeiro.');
      return false;
    }

    final revision = _sessionRevision;
    _loginPending = true;
    final releaseCloseGuard = WindowCloseGuard.acquire();
    try {
      final ok = await runAsync<bool>(
        action: () async {
          final rd.Result<TAuthResult> result;
          try {
            result = await _signInService();
          } on Object {
            if (revision != _sessionRevision) return false;
            rethrow;
          }
          if (revision != _sessionRevision) return false;
          return result.fold(
            (authResult) {
              _currentEmail = emailOf(authResult);
              LoggerService.info(
                'Login $serviceLabel realizado: $_currentEmail',
              );
              return true;
            },
            (exception) => throw exception,
          );
        },
      );
      return ok ?? false;
    } finally {
      _loginPending = false;
      releaseCloseGuard();
    }
  }

  Future<void> signOut() {
    _sessionRevision++;
    return _serializeConfiguration(_signOut);
  }

  Future<void> _signOut() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao fazer logout',
      action: () async {
        await _signOutService();
        _currentEmail = null;
        LoggerService.info('Logout $serviceLabel realizado');
      },
    );
  }

  Future<bool> removeOAuthConfig() {
    _sessionRevision++;
    return _serializeConfiguration(_removeOAuthConfig);
  }

  Future<bool> _removeOAuthConfig() async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao remover configuração',
      action: () async {
        await _signOutService();
        _currentEmail = null;
        try {
          await removePersistedConfig();
        } on Object {
          _isInitialized = false;
          Map<String, dynamic>? persisted;
          try {
            persisted = await loadPersistedConfig();
            if (persisted != null) {
              final restored = configFromJson(persisted);
              final previous = _oauthConfig;
              if (previous == null ||
                  !mapEquals(configToJson(restored), configToJson(previous))) {
                _isConfigured = false;
              }
            }
          } on Object {
            _isConfigured = false;
            rethrow;
          }
          if (persisted != null) rethrow;
        }
        _oauthConfig = null;
        _isConfigured = false;
        _currentEmail = null;
        LoggerService.info('Configuração OAuth $serviceLabel removida');
        return true;
      },
    );
    return ok ?? false;
  }

  Future<void> _loadOAuthConfig() async {
    try {
      final json = await loadPersistedConfig();
      if (json == null) {
        _oauthConfig = null;
        return;
      }
      _oauthConfig = configFromJson(json);
      LoggerService.debug('Configuração OAuth $serviceLabel carregada');
    } on Object catch (e, s) {
      // Sem fail silencioso: registra erro e expõe para a UI para que o
      // operador saiba que precisa reconfigurar credenciais OAuth.
      setErrorManual(
        'Configuração OAuth corrompida ou inválida. '
        'Reconfigure as credenciais.',
      );
      LoggerService.error(
        'Erro ao carregar configuração OAuth $serviceLabel',
        e,
        s,
      );
      rethrow;
    }
  }

  Future<void> _saveOAuthConfig(TConfig config) async {
    try {
      await savePersistedConfig(configToJson(config));
    } on Object catch (e) {
      _isInitialized = false;
      Map<String, dynamic>? persisted;
      try {
        persisted = await loadPersistedConfig();
        if (persisted != null) {
          persisted = configToJson(configFromJson(persisted));
        }
      } on Object {
        _isConfigured = false;
        rethrow;
      }
      if (mapEquals(persisted, configToJson(config))) return;
      final previous = _oauthConfig;
      if (previous == null || !mapEquals(persisted, configToJson(previous))) {
        _isConfigured = false;
      }
      LoggerService.error(
        'Erro ao salvar configuração OAuth $serviceLabel',
        e,
      );
      rethrow;
    }
  }
}
