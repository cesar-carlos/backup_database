import 'dart:async';
import 'dart:convert';

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter/foundation.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Callback que inicializa o auth service concreto (Google/Dropbox).
typedef OAuthInitializeCallback =
    Future<void> Function({required String clientId, String? clientSecret});

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
    required OAuthInitializeCallback initializeService,
    required OAuthSignInCallback<TAuthResult> signInService,
    required OAuthSignInCallback<TAuthResult> signInSilentlyService,
    required OAuthSignOutCallback signOutService,
  }) : _initializeService = initializeService,
       _signInService = signInService,
       _signInSilentlyService = signInSilentlyService,
       _signOutService = signOutService;

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

  bool get isInitialized => _isInitialized;
  bool get isConfigured => _isConfigured;
  String? get currentEmail => _currentEmail ?? currentUserEmailFromService;
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
    return _initializeFuture = _doInitialize().whenComplete(() {
      _initializeFuture = null;
    });
  }

  Future<void> _doInitialize() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao inicializar',
      action: () async {
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
  }) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao configurar OAuth',
      action: () async {
        _oauthConfig = buildConfig(
          clientId: clientId,
          clientSecret: clientSecret,
        );
        await _saveOAuthConfig();
        await _initializeService(
          clientId: clientId,
          clientSecret: clientSecret,
        );
        _isConfigured = true;
        LoggerService.info('Configuração OAuth $serviceLabel salva');
        return true;
      },
    );
    return ok ?? false;
  }

  /// Login interativo. Protege a janela contra fechamento durante o
  /// fluxo OAuth (o webview pode disparar `windowClose` inesperados).
  Future<bool> signIn() async {
    if (!_isConfigured) {
      setErrorManual('Configure as credenciais OAuth primeiro.');
      return false;
    }

    await _setWindowPreventClose(true);
    try {
      final ok = await runAsync<bool>(
        action: () async {
          final result = await _signInService();
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
      await _setWindowPreventClose(false);
    }
  }

  Future<void> signOut() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao fazer logout',
      action: () async {
        await _signOutService();
        _currentEmail = null;
        LoggerService.info('Logout $serviceLabel realizado');
      },
    );
  }

  Future<bool> removeOAuthConfig() async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao remover configuração',
      action: () async {
        await _signOutService();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(oauthConfigPrefsKey);
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
      final prefs = await SharedPreferences.getInstance();
      final encryptedConfig = prefs.getString(oauthConfigPrefsKey);
      if (encryptedConfig == null) return;

      final decryptedConfig = EncryptionService.decrypt(encryptedConfig);
      final json = jsonDecode(decryptedConfig) as Map<String, dynamic>;
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
    }
  }

  Future<void> _saveOAuthConfig() async {
    final config = _oauthConfig;
    if (config == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(configToJson(config));
      final encryptedConfig = EncryptionService.encrypt(json);
      await prefs.setString(oauthConfigPrefsKey, encryptedConfig);
    } on Object catch (e) {
      LoggerService.error(
        'Erro ao salvar configuração OAuth $serviceLabel',
        e,
      );
      rethrow;
    }
  }

  /// Set window-level `preventClose` defensivo durante OAuth flow.
  /// Best-effort — falhas viram debug log (`window_manager` pode não
  /// estar inicializado em ambientes de teste/headless).
  Future<void> _setWindowPreventClose(bool enable) async {
    try {
      await windowManager.setPreventClose(enable);
      LoggerService.debug(
        enable
            ? 'Proteção contra fechamento ativada para OAuth $serviceLabel'
            : 'Proteção contra fechamento desativada ($serviceLabel)',
      );
    } on Object catch (e) {
      LoggerService.debug(
        'Window manager setPreventClose ($enable, $serviceLabel): $e',
      );
    }
  }
}
