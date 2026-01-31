import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2_client/access_token_response.dart';
import 'package:oauth2_client/google_oauth2_client.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const _storageKey = 'google_oauth_credentials';
  static const _emailStorageKey = 'google_oauth_email';

  String? _clientId;
  String? _clientSecret;

  GoogleOAuth2Client? _client;
  OAuth2Helper? _helper;

  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  String? _cachedEmail;
  DateTime? _tokenExpiration;

  bool _isInitialized = false;

  Future<void> initialize({
    required String clientId,
    String? clientSecret,
  }) async {
    _clientId = clientId;
    _clientSecret = clientSecret;

    _client = GoogleOAuth2Client(
      redirectUri: AppConstants.oauthRedirectUri,
      customUriScheme: 'http://localhost:${AppConstants.oauthLoopbackPort}',
    );

    _helper = OAuth2Helper(
      _client!,
      clientId: _clientId!,
      clientSecret: _clientSecret,
      scopes: AppConstants.googleDriveScopes,
    );

    await _loadStoredCredentials();
    _isInitialized = true;

    LoggerService.info('GoogleAuthService inicializado');
  }

  Future<rd.Result<GoogleAuthResult>> signIn() async {
    if (!_isInitialized) {
      return const rd.Failure(
        GoogleDriveFailure(
          message:
              'GoogleAuthService não inicializado. '
              'Chame initialize() primeiro.',
        ),
      );
    }

    try {
      LoggerService.info(
        'Iniciando autenticação Google OAuth2 (navegador externo)',
      );

      // Usar fluxo manual com navegador externo para evitar problemas com webview
      final tokenResponse = await _getTokenWithExternalBrowser();

      if (tokenResponse == null || tokenResponse.accessToken == null) {
        return const rd.Failure(
          GoogleDriveFailure(
            message: 'Falha ao obter token de acesso do Google.',
          ),
        );
      }

      _cachedAccessToken = tokenResponse.accessToken;
      _cachedRefreshToken = tokenResponse.refreshToken;
      _tokenExpiration = tokenResponse.expirationDate;

      final emailResult = await _fetchUserEmail(tokenResponse.accessToken!);
      if (emailResult.isError()) {
        return rd.Failure(emailResult.exceptionOrNull()!);
      }

      _cachedEmail = emailResult.getOrNull();

      await _saveCredentials(tokenResponse, _cachedEmail!);

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
    }
  }

  Future<AccessTokenResponse?> _getTokenWithExternalBrowser() async {
    HttpServer? server;

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
      );

      LoggerService.debug('Abrindo navegador para autenticação');

      // Abrir navegador externo
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Não foi possível abrir o navegador');
      }

      // Aguardar callback com timeout
      final request = await server.first.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw Exception('Tempo limite de autenticação excedido');
        },
      );

      // Extrair código de autorização
      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];

      // Responder ao navegador
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_getSuccessHtml(error == null));
      await request.response.close();

      if (error != null) {
        throw Exception('Erro de autenticação: $error');
      }

      if (code == null) {
        throw Exception('Código de autorização não recebido');
      }

      LoggerService.debug('Código de autorização recebido, trocando por token');

      // Trocar código por token usando HTTP direto
      final tokenResponse = await _exchangeCodeForToken(code);

      return tokenResponse;
    } finally {
      await server?.close();
      LoggerService.debug('Servidor OAuth encerrado');
    }
  }

  Future<AccessTokenResponse?> _exchangeCodeForToken(String code) async {
    try {
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'code': code,
          'client_id': _clientId!,
          'client_secret': _clientSecret ?? '',
          'redirect_uri': AppConstants.oauthRedirectUri,
          'grant_type': 'authorization_code',
        },
      );

      if (response.statusCode != 200) {
        LoggerService.error('Erro ao trocar código: ${response.body}');
        throw Exception(
          'Falha ao trocar código por token: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      return AccessTokenResponse.fromMap(data);
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

  Future<rd.Result<GoogleAuthResult>> signInSilently() async {
    if (!_isInitialized) {
      return const rd.Failure(
        GoogleDriveFailure(message: 'GoogleAuthService não inicializado.'),
      );
    }

    try {
      if (_cachedAccessToken != null && _cachedEmail != null) {
        if (_isTokenExpired()) {
          LoggerService.debug('Token expirado, tentando refresh');
          final refreshResult = await _refreshToken();
          if (refreshResult.isError()) {
            return refreshResult;
          }
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

  Future<rd.Result<GoogleAuthResult>> _refreshToken() async {
    if (_cachedRefreshToken == null || _helper == null) {
      return const rd.Failure(
        GoogleDriveFailure(message: 'Não há refresh token disponível.'),
      );
    }

    try {
      LoggerService.debug('Executando refresh do token');

      final tokenResponse = await _helper!.getToken();

      if (tokenResponse == null || tokenResponse.accessToken == null) {
        await _clearStoredCredentials();
        return const rd.Failure(
          GoogleDriveFailure(message: 'Sessão expirada. Faça login novamente.'),
        );
      }

      _cachedAccessToken = tokenResponse.accessToken;
      _cachedRefreshToken = tokenResponse.refreshToken ?? _cachedRefreshToken;
      _tokenExpiration = tokenResponse.expirationDate;

      await _saveCredentials(tokenResponse, _cachedEmail!);

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
      await _clearStoredCredentials();
      return rd.Failure(
        GoogleDriveFailure(
          message: 'Falha ao atualizar sessão. Faça login novamente.',
          originalError: e,
        ),
      );
    }
  }

  Future<void> signOut() async {
    try {
      if (_helper != null) {
        await _helper!.removeAllTokens();
      }
    } on Object catch (e) {
      LoggerService.warning('Erro ao revogar tokens: $e');
    }

    await _clearStoredCredentials();

    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _cachedEmail = null;
    _tokenExpiration = null;

    LoggerService.info('Desconectado do Google');
  }

  bool get isSignedIn => _cachedAccessToken != null && _cachedEmail != null;

  String? get currentUserEmail => _cachedEmail;

  String? get accessToken => _cachedAccessToken;

  bool _isTokenExpired() {
    if (_tokenExpiration == null) return false;
    return DateTime.now().isAfter(
      _tokenExpiration!.subtract(const Duration(minutes: 5)),
    );
  }

  Future<rd.Result<String>> _fetchUserEmail(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

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
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final credentials = {
        'accessToken': tokenResponse.accessToken,
        'refreshToken': tokenResponse.refreshToken,
        'expirationDate': tokenResponse.expirationDate?.toIso8601String(),
      };

      final encryptedData = EncryptionService.encrypt(jsonEncode(credentials));
      await prefs.setString(_storageKey, encryptedData);
      await prefs.setString(_emailStorageKey, email);

      LoggerService.debug('Credenciais Google salvas');
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar credenciais', e);
    }
  }

  Future<void> _loadStoredCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final encryptedData = prefs.getString(_storageKey);
      final storedEmail = prefs.getString(_emailStorageKey);

      if (encryptedData == null || storedEmail == null) {
        return;
      }

      final decryptedData = EncryptionService.decrypt(encryptedData);
      final credentials = jsonDecode(decryptedData) as Map<String, dynamic>;

      _cachedAccessToken = credentials['accessToken'] as String?;
      _cachedRefreshToken = credentials['refreshToken'] as String?;
      _cachedEmail = storedEmail;

      if (credentials['expirationDate'] != null) {
        _tokenExpiration = DateTime.parse(
          credentials['expirationDate'] as String,
        );
      }

      LoggerService.debug('Credenciais Google carregadas: $_cachedEmail');
    } on Object catch (e) {
      LoggerService.warning('Erro ao carregar credenciais: $e');
      await _clearStoredCredentials();
    }
  }

  Future<void> _clearStoredCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      await prefs.remove(_emailStorageKey);
      LoggerService.debug('Credenciais Google removidas');
    } on Object catch (e) {
      LoggerService.error('Erro ao limpar credenciais', e);
    }
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
    _cachedAccessToken = accessToken;
    _cachedEmail = email;
    _cachedRefreshToken = refreshToken;
    LoggerService.debug('Credenciais definidas manualmente para: $email');
  }
}
