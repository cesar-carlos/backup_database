import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/google/google_oauth_config_store.dart';
import 'package:backup_database/infrastructure/external/oauth/oauth_loopback_callback.dart';
import 'package:backup_database/infrastructure/external/oauth/oauth_session_lock.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2_client/access_token_response.dart';
import 'package:oauth2_client/google_oauth2_client.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:uuid/uuid.dart';

class GoogleAuthResult {
  const GoogleAuthResult({
    required this.accessToken,
    required this.email,
    this.refreshToken,
    this.expirationDate,
  });

  factory GoogleAuthResult.fromJson(Map<String, dynamic> json) {
    return GoogleAuthResult(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      email: json['email'] as String,
      expirationDate: json['expirationDate'] != null
          ? DateTime.parse(json['expirationDate'] as String)
          : null,
    );
  }
  final String accessToken;
  final String? refreshToken;
  final String email;
  final DateTime? expirationDate;

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'email': email,
    'expirationDate': expirationDate?.toIso8601String(),
  };
}

class GoogleAuthService {
  GoogleAuthService(
    this._secureCredentialService, {
    this.httpClient,
    this.requestTimeout = const Duration(seconds: 30),
    this.authorize,
    this.launchBrowser,
    this.configurationStore,
    OAuthSessionLock? sessionLock,
  }) : _sessionLock =
           sessionLock ?? OAuthSessionLock(fileName: 'google-session.lock');

  final OAuthSessionLock _sessionLock;
  final Future<bool> Function(Uri)? launchBrowser;
  OAuthLoopbackCallback? _browserCallback;
  Completer<void>? _browserCleanup;
  Future<void>? _logoutInFlight;
  Map<String, dynamic>? _tokenSnapshot;

  final http.Client? httpClient;
  final GoogleOAuthConfigStore? configurationStore;
  Future<void>? _headlessInitialization;
  final Duration requestTimeout;
  final Future<AccessTokenResponse?> Function()? authorize;
  bool _loginPending = false;
  Future<rd.Result<GoogleAuthResult>>? _refreshInFlight;
  Future<void> _storageTail = Future<void>.value();
  int _generation = 0;

  Future<T> _withStorage<T>(Future<T> Function() action) {
    if (configurationStore != null) return _sessionLock.run(action);
    final result = _storageTail.then((_) => action());
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _checkGeneration(int generation) {
    if (generation != _generation) {
      throw StateError('A sessão Google mudou durante a operação.');
    }
  }

  void _invalidate() {
    _browserCallback?.cancel();
    _tokenSnapshot = null;
    _generation++;
    _loginPending = false;
    _refreshInFlight = null;
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _cachedEmail = null;
    _tokenExpiration = null;
  }

  static const _tokenKey = 'google_oauth_token';

  String? _clientId;
  String? _clientSecret;

  GoogleOAuth2Client? _client;
  final ISecureCredentialService _secureCredentialService;

  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  String? _cachedEmail;
  DateTime? _tokenExpiration;

  bool _isInitialized = false;

  Future<void> initialize({
    required String clientId,
    String? clientSecret,
  }) async {
    _invalidate();
    _isInitialized = false;
    final generation = _generation;
    _clientId = clientId;
    _clientSecret = clientSecret;

    _client = GoogleOAuth2Client(
      redirectUri: AppConstants.oauthRedirectUri,
      customUriScheme: 'http://localhost:${AppConstants.oauthLoopbackPort}',
    );

    await _withStorage(() => _loadStoredCredentials(generation));
    _checkGeneration(generation);
    _isInitialized = true;

    LoggerService.info('GoogleAuthService inicializado');
  }

  Future<rd.Result<GoogleAuthResult>> signIn() async {
    if (_loginPending) {
      return const rd.Failure(
        GoogleDriveFailure(message: 'Login Google em andamento.'),
      );
    }
    if (!_isInitialized) {
      return const rd.Failure(
        GoogleDriveFailure(
          message:
              'GoogleAuthService não inicializado. '
              'Chame initialize() primeiro.',
        ),
      );
    }

    final generation = ++_generation;
    _loginPending = true;
    _refreshInFlight = null;
    try {
      await _logoutInFlight;
      await _browserCleanup?.future;
      _checkGeneration(generation);
      final expectedToken = configurationStore == null
          ? null
          : await _withStorage(() async {
              _checkGeneration(generation);
              return _readSharedToken();
            });
      _checkGeneration(generation);
      LoggerService.info(
        'Iniciando autenticação Google OAuth2 (navegador externo)',
      );

      // Usar fluxo manual com navegador externo para evitar problemas com webview
      final tokenResponse = await (authorize ?? _getTokenWithExternalBrowser)();
      _checkGeneration(generation);

      if (tokenResponse == null ||
          tokenResponse.accessToken?.isNotEmpty != true) {
        return const rd.Failure(
          GoogleDriveFailure(
            message: 'Falha ao obter token de acesso do Google.',
          ),
        );
      }

      final emailResult = await _fetchUserEmail(tokenResponse.accessToken!);
      if (emailResult.isError()) {
        return rd.Failure(emailResult.exceptionOrNull()!);
      }

      _checkGeneration(generation);
      final email = emailResult.getOrThrow();
      if (tokenResponse.refreshToken?.isNotEmpty != true) {
        throw StateError(
          'Google não retornou autorização offline. '
          'Autorize novamente o acesso.',
        );
      }
      await _saveCredentials(
        tokenResponse,
        email,
        generation,
        expectedToken: expectedToken,
        replaceSession: true,
      );
      _checkGeneration(generation);
      _cachedAccessToken = tokenResponse.accessToken;
      _cachedRefreshToken = tokenResponse.refreshToken;
      _tokenExpiration = tokenResponse.expirationDate;
      _cachedEmail = email;

      LoggerService.info('Autenticação Google concluída: $_cachedEmail');

      return rd.Success(
        GoogleAuthResult(
          accessToken: _cachedAccessToken!,
          refreshToken: _cachedRefreshToken,
          email: _cachedEmail!,
          expirationDate: _tokenExpiration,
        ),
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro na autenticação Google', e, stackTrace);
      return rd.Failure(
        GoogleDriveFailure(message: _parseAuthError(e), originalError: e),
      );
    } finally {
      if (generation == _generation) _loginPending = false;
    }
  }

  Future<AccessTokenResponse?> _getTokenWithExternalBrowser() async {
    HttpServer? server;
    final generation = _generation;
    final callback = OAuthLoopbackCallback(
      redirectUri: Uri.parse(AppConstants.oauthRedirectUri),
    );
    _browserCallback = callback;
    final cleanup = Completer<void>();
    _browserCleanup = cleanup;

    try {
      // Criar servidor HTTP local para receber o callback
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        AppConstants.oauthLoopbackPort,
      );

      LoggerService.debug(
        'Servidor OAuth iniciado na porta ${AppConstants.oauthLoopbackPort}',
      );

      // Gerar URL de autenticação
      final authUrl = _client!.getAuthorizeUrl(
        clientId: _clientId!,
        redirectUri: AppConstants.oauthRedirectUri,
        scopes: AppConstants.googleDriveScopes,
        customParams: {
          'access_type': 'offline',
          'prompt': 'consent',
          'state': callback.state,
          'code_challenge': callback.codeChallenge,
          'code_challenge_method': 'S256',
        },
      );

      LoggerService.debug('Abrindo navegador para autenticação');

      // Abrir navegador externo
      final uri = Uri.parse(authUrl);
      if (!await callback.waitFor((launchBrowser ?? launchOAuthBrowser)(uri))) {
        throw StateError('Não foi possível abrir o navegador');
      }

      // Aguardar callback com timeout
      final code = await callback.receive(
        server,
        responseHtml: _getSuccessHtml,
      );

      _checkGeneration(generation);
      final tokenResponse = await callback.waitFor(
        _exchangeCodeForToken(
          code,
          callback.codeVerifier,
        ),
      );

      return tokenResponse;
    } finally {
      try {
        await server?.close(force: true);
      } finally {
        if (identical(_browserCallback, callback)) {
          _browserCallback = null;
          _browserCleanup = null;
        }
        cleanup.complete();
      }
      LoggerService.debug('Servidor OAuth encerrado');
    }
  }

  Future<AccessTokenResponse?> _exchangeCodeForToken(
    String code,
    String codeVerifier,
  ) async {
    try {
      final response = await (httpClient?.post ?? http.post)(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'code': code,
          'code_verifier': codeVerifier,
          'client_id': _clientId!,
          'client_secret': _clientSecret ?? '',
          'redirect_uri': AppConstants.oauthRedirectUri,
          'grant_type': 'authorization_code',
        },
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception(
          'Falha ao trocar código por token: ${response.statusCode}',
        );
      }

      return AccessTokenResponse.fromHttpResponse(response);
    } on Object catch (e) {
      LoggerService.error('Erro ao trocar código por token', e);
      rethrow;
    }
  }

  String _getSuccessHtml(bool success) {
    if (success) {
      return '''
<!DOCTYPE html>
<html>
<head>
  <title>Autenticação Concluída</title>
  <style>
    body { font-family: Arial, sans-serif; text-align: center; padding: 50px; background: #1a1a2e; color: #eee; }
    .success { color: #4ade80; font-size: 24px; }
    .message { margin-top: 20px; color: #888; }
  </style>
</head>
<body>
  <div class="success">✓ Autenticação realizada com sucesso!</div>
  <div class="message">Você pode fechar esta janela e voltar ao aplicativo.</div>
  <script>setTimeout(function() { window.close(); }, 3000);</script>
</body>
</html>
''';
    } else {
      return '''
<!DOCTYPE html>
<html>
<head>
  <title>Erro de Autenticação</title>
  <style>
    body { font-family: Arial, sans-serif; text-align: center; padding: 50px; background: #1a1a2e; color: #eee; }
    .error { color: #f87171; font-size: 24px; }
    .message { margin-top: 20px; color: #888; }
  </style>
</head>
<body>
  <div class="error">✗ Erro na autenticação</div>
  <div class="message">A autenticação foi cancelada ou ocorreu um erro. Por favor, tente novamente.</div>
</body>
</html>
''';
    }
  }

  Future<rd.Result<GoogleAuthResult>> signInSilently({
    bool forceRefresh = false,
  }) async {
    if (_loginPending) {
      return const rd.Failure(
        GoogleDriveFailure(message: 'Login Google em andamento.'),
      );
    }
    try {
      final refreshing = _refreshInFlight;
      if (refreshing != null) return await refreshing;
      if (configurationStore != null) {
        await (_headlessInitialization ??= _initializeFromSharedConfig()
            .whenComplete(() => _headlessInitialization = null));
      }
    } on Object catch (e) {
      return rd.Failure(
        GoogleDriveFailure(
          message:
              'Não foi possível carregar a configuração Google do servidor. '
              'Verifique o acesso ao armazenamento de credenciais.',
          originalError: e,
        ),
      );
    }
    if (!_isInitialized) {
      return const rd.Failure(
        GoogleDriveFailure(
          message:
              'Configuração Google Drive indisponível no servidor. '
              'Abra a interface e configure a conexão Google do destino.',
        ),
      );
    }

    try {
      if (_cachedAccessToken != null && _cachedEmail != null) {
        if (forceRefresh || _cachedAccessToken!.isEmpty || _isTokenExpired()) {
          LoggerService.debug('Token expirado, tentando refresh');
          final generation = _generation;
          return await (_refreshInFlight ??= _refreshToken(generation)
              .whenComplete(() {
                if (generation == _generation) _refreshInFlight = null;
              }));
        }

        return rd.Success(
          GoogleAuthResult(
            accessToken: _cachedAccessToken!,
            refreshToken: _cachedRefreshToken,
            email: _cachedEmail!,
            expirationDate: _tokenExpiration,
          ),
        );
      }

      return const rd.Failure(
        GoogleDriveFailure(message: 'Nenhuma conta Google autenticada.'),
      );
    } on Object catch (e) {
      LoggerService.error('Erro ao autenticar silenciosamente', e);
      return rd.Failure(
        GoogleDriveFailure(
          message: 'Erro ao restaurar sessão: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<void> _initializeFromSharedConfig() async {
    final generation = _generation;
    final config = await configurationStore!.read();
    _checkGeneration(generation);
    if (config == null) {
      _invalidate();
      _isInitialized = false;
      return;
    }
    if (!_isInitialized ||
        _clientId != config['clientId'] ||
        _clientSecret != config['clientSecret']) {
      await initialize(
        clientId: config['clientId'] as String,
        clientSecret: config['clientSecret'] as String?,
      );
      return;
    }
    // Login/logout in the UI must be visible to an already-running service.
    await _withStorage(() async {
      final exists = (await _secureCredentialService.containsKey(
        key: _tokenKey,
      )).getOrThrow();
      _checkGeneration(generation);
      if (!exists) {
        _cachedAccessToken = null;
        _cachedRefreshToken = null;
        _cachedEmail = null;
        _tokenExpiration = null;
        return;
      }
      await _loadStoredCredentials(generation, failOnReadError: true);
    });
  }

  Future<rd.Result<GoogleAuthResult>> _refreshToken(int generation) async {
    final expectedToken = _tokenSnapshot == null
        ? null
        : Map<String, dynamic>.of(_tokenSnapshot!);
    if (_cachedRefreshToken == null || _cachedRefreshToken!.isEmpty) {
      return const rd.Failure(
        GoogleDriveFailure(message: 'Não há refresh token disponível.'),
      );
    }

    try {
      LoggerService.debug('Executando refresh do token');

      // The browser flow stores credentials in our secure store, not in
      // OAuth2Helper's independent token storage. Refresh that exact credential.
      final response = await (httpClient?.post ?? http.post)(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': _cachedRefreshToken!,
          'client_id': _clientId!,
          if (_clientSecret?.isNotEmpty ?? false)
            'client_secret': _clientSecret!,
        },
      ).timeout(requestTimeout);
      _checkGeneration(generation);
      if (response.statusCode != 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return rd.Failure(
          GoogleDriveFailure(
            message: data['error'] == 'invalid_grant'
                ? 'Autorização Google revogada ou expirada. Faça login novamente.'
                : 'Não foi possível renovar o acesso ao Google '
                      '(HTTP ${response.statusCode}). Tente novamente.',
          ),
        );
      }
      final tokenResponse = AccessTokenResponse.fromHttpResponse(response);

      if (tokenResponse.accessToken?.isNotEmpty != true ||
          tokenResponse.expirationDate == null ||
          !tokenResponse.expirationDate!.isAfter(DateTime.now())) {
        return const rd.Failure(
          GoogleDriveFailure(
            message:
                'Resposta inválida ao renovar acesso Google. Tente novamente.',
          ),
        );
      }

      if (tokenResponse.refreshToken?.isNotEmpty != true) {
        tokenResponse.refreshToken = _cachedRefreshToken;
      }
      await _saveCredentials(
        tokenResponse,
        _cachedEmail!,
        generation,
        expectedToken: expectedToken,
      );
      _checkGeneration(generation);
      _cachedAccessToken = tokenResponse.accessToken;
      _cachedRefreshToken = tokenResponse.refreshToken;
      _tokenExpiration = tokenResponse.expirationDate;

      LoggerService.info('Token Google atualizado com sucesso');

      return rd.Success(
        GoogleAuthResult(
          accessToken: _cachedAccessToken!,
          refreshToken: _cachedRefreshToken,
          email: _cachedEmail!,
          expirationDate: _tokenExpiration,
        ),
      );
    } on Object catch (e) {
      LoggerService.error('Erro ao atualizar token', e);
      return rd.Failure(
        GoogleDriveFailure(
          message: 'Falha ao renovar o acesso ao Google. Tente novamente.',
          originalError: e,
        ),
      );
    }
  }

  Future<void> signOut() {
    final pending = _logoutInFlight;
    if (pending != null) {
      _invalidate();
      return pending;
    }
    late final Future<void> operation;
    operation = _signOut().whenComplete(() {
      if (identical(_logoutInFlight, operation)) _logoutInFlight = null;
    });
    return _logoutInFlight = operation;
  }

  Future<void> _signOut() async {
    final browserCleanup = _browserCleanup?.future;
    _browserCallback?.cancel();
    _invalidate();
    await browserCleanup;
    await _withStorage(_clearStoredCredentials);

    LoggerService.info('Desconectado do Google');
  }

  bool get isSignedIn => _cachedAccessToken != null && _cachedEmail != null;

  String? get currentUserEmail => _cachedEmail;

  String? get accessToken => _cachedAccessToken;

  bool _isTokenExpired() {
    if (_tokenExpiration == null) return true;
    return DateTime.now().isAfter(
      _tokenExpiration!.subtract(const Duration(minutes: 5)),
    );
  }

  Future<rd.Result<String>> _fetchUserEmail(String accessToken) async {
    try {
      final response = await (httpClient?.get ?? http.get)(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final email = data['email'] as String?;

        if (email == null || email.isEmpty) {
          return const rd.Failure(
            GoogleDriveFailure(message: 'Email não encontrado na resposta.'),
          );
        }

        return rd.Success(email);
      }

      return rd.Failure(
        GoogleDriveFailure(
          message: 'Erro ao obter email: ${response.statusCode}',
        ),
      );
    } on Object catch (e) {
      return rd.Failure(
        GoogleDriveFailure(
          message: 'Erro ao obter informações do usuário: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<void> _saveCredentials(
    AccessTokenResponse tokenResponse,
    String email,
    int generation, {
    Map<String, dynamic>? expectedToken,
    bool replaceSession = false,
  }) => _withStorage(() async {
    _checkGeneration(generation);
    if (expectedToken != null) {
      final current = configurationStore == null
          ? (await _secureCredentialService.getToken(key: _tokenKey))
                .getOrThrow()
          : await _readSharedToken();
      _checkGeneration(generation);
      final sameSession =
          replaceSession &&
          expectedToken['sessionId'] is String &&
          (expectedToken['sessionId'] as String).isNotEmpty &&
          current['sessionId'] == expectedToken['sessionId'] &&
          current['clientId'] == expectedToken['clientId'] &&
          current['signedOut'] == expectedToken['signedOut'];
      if (!sameSession && !mapEquals(current, expectedToken)) {
        _invalidate();
        throw StateError(
          'A sessão Google foi alterada por outro processo. Tente novamente.',
        );
      }
    }
    final credentials = {
      'sessionId': replaceSession
          ? const Uuid().v4()
          : expectedToken?['sessionId'] ?? const Uuid().v4(),
      'accessToken': tokenResponse.accessToken,
      'refreshToken': tokenResponse.refreshToken,
      'expirationDate': tokenResponse.expirationDate?.toIso8601String(),
      'email': email,
      'clientId': _clientId,
    };

    final result = await _secureCredentialService.storeToken(
      key: _tokenKey,
      tokenData: credentials,
    );

    if (result.isError()) {
      // Storage can commit the machine credential and then fail while
      // removing a legacy copy. Reconcile before discarding a rotated token.
      final persisted = await _secureCredentialService.getToken(key: _tokenKey);
      _checkGeneration(generation);
      if (persisted.isError() ||
          !mapEquals(persisted.getOrNull(), credentials)) {
        throw StateError(
          'Falha ao confirmar a gravação das credenciais Google.',
        );
      }
      LoggerService.warning(
        'Gravação Google confirmada após erro do armazenamento.',
      );
    }

    _checkGeneration(generation);
    LoggerService.debug('Credenciais Google salvas');
    _tokenSnapshot = Map<String, dynamic>.of(credentials);
  });

  Future<Map<String, dynamic>> _readSharedToken() async {
    final exists = (await _secureCredentialService.containsKey(key: _tokenKey))
        .getOrThrow();
    if (!exists) return <String, dynamic>{};
    return (await _secureCredentialService.getToken(key: _tokenKey))
        .getOrThrow();
  }

  Future<void> _loadStoredCredentials(
    int generation, {
    bool failOnReadError = false,
  }) async {
    final result = await _secureCredentialService.getToken(key: _tokenKey);
    _checkGeneration(generation);

    if (result.isError()) {
      if (failOnReadError) throw result.exceptionOrNull()!;
      return;
    }

    final credentials = result.getOrElse((_) => <String, dynamic>{});
    if (credentials.containsKey('signedOut')) {
      _cachedAccessToken = null;
      _cachedRefreshToken = null;
      _cachedEmail = null;
      _tokenExpiration = null;
      _tokenSnapshot = null;
      final sessionId = credentials['sessionId'];
      if (credentials['signedOut'] != true ||
          sessionId is! String ||
          sessionId.isEmpty) {
        throw const FormatException(
          'Marcador de encerramento Google inválido.',
        );
      }
      _tokenSnapshot = Map<String, dynamic>.of(credentials);
      return;
    }
    if (credentials['clientId'] != null &&
        credentials['clientId'] != _clientId) {
      _cachedAccessToken = null;
      _cachedRefreshToken = null;
      _cachedEmail = null;
      _tokenExpiration = null;
      return;
    }

    final accessToken = credentials['accessToken'] as String?;
    final refreshToken = credentials['refreshToken'] as String?;
    final email = credentials['email'] as String?;
    final expiration = credentials['expirationDate'] as String?;
    final expirationDate = expiration == null
        ? null
        : DateTime.tryParse(expiration);

    _cachedAccessToken = accessToken;
    _cachedRefreshToken = refreshToken;
    _cachedEmail = email;
    _tokenExpiration = expirationDate;
    _tokenSnapshot = Map<String, dynamic>.of(credentials);

    LoggerService.debug('Credenciais Google carregadas: $_cachedEmail');
  }

  Future<void> _clearStoredCredentials() async {
    if (configurationStore != null) {
      // Keep a secret-free revision so logout also invalidates a browser login
      // that started when no credentials existed in another process.
      final signedOut = <String, dynamic>{
        'sessionId': const Uuid().v4(),
        'signedOut': true,
      };
      final result = await _secureCredentialService.storeToken(
        key: _tokenKey,
        tokenData: signedOut,
      );
      if (result.isError()) {
        final persisted = await _secureCredentialService.getToken(
          key: _tokenKey,
        );
        if (persisted.isError() ||
            !mapEquals(persisted.getOrNull(), signedOut)) {
          throw StateError(
            'Falha ao persistir o encerramento da sessão Google. Tente novamente.',
          );
        }
      }
      LoggerService.debug('Encerramento da sessão Google persistido');
      return;
    }
    final result = await _secureCredentialService.deleteToken(key: _tokenKey);
    if (result.isError()) {
      throw StateError(
        'Falha ao remover credenciais Google salvas. Tente novamente.',
      );
    }
    LoggerService.debug('Credenciais Google removidas');
  }

  String _parseAuthError(dynamic e) {
    final errorStr = e.toString().toLowerCase();

    if (errorStr.contains('user_cancelled') ||
        errorStr.contains('access_denied')) {
      return 'Autenticação cancelada pelo usuário.';
    }

    if (errorStr.contains('invalid_client')) {
      return 'Configuração OAuth inválida. Verifique o Client ID.';
    }

    if (errorStr.contains('invalid_grant')) {
      return 'Sessão expirada. Faça login novamente.';
    }

    if (errorStr.contains('network') || errorStr.contains('connection')) {
      return 'Erro de conexão. Verifique sua internet.';
    }

    if (errorStr.contains('timeout')) {
      return 'Tempo limite excedido. Tente novamente.';
    }

    return 'Erro na autenticação Google: $e';
  }

  void setCredentials(
    String accessToken,
    String email, {
    String? refreshToken,
  }) {
    _invalidate();
    _cachedAccessToken = accessToken;
    _cachedEmail = email;
    _cachedRefreshToken = refreshToken;
    LoggerService.debug('Credenciais definidas manualmente para: $email');
  }
}
