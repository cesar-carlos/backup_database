import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:dio/dio.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class DropboxAuthResult {
  const DropboxAuthResult({
    required this.accessToken,
    required this.email,
    this.refreshToken,
    this.expirationDate,
  });

  factory DropboxAuthResult.fromJson(Map<String, dynamic> json) {
    return DropboxAuthResult(
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

class DropboxAuthService {
  static const _storageKey = 'dropbox_oauth_credentials';
  static const _emailStorageKey = 'dropbox_oauth_email';

  String? _clientId;
  String? _clientSecret;

  Dio? _dio;

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

    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.dropbox.com',
        connectTimeout: AppConstants.httpTimeout,
        receiveTimeout: AppConstants.httpTimeout,
      ),
    );

    await _loadStoredCredentials();
    _isInitialized = true;
  }

  Future<rd.Result<DropboxAuthResult>> signIn() async {
    if (!_isInitialized) {
      return const rd.Failure(
        DropboxFailure(
          message:
              'DropboxAuthService não inicializado. '
              'Chame initialize() primeiro.',
        ),
      );
    }

    try {
      final tokenResponse = await _getTokenWithExternalBrowser();

      if (tokenResponse == null || tokenResponse['access_token'] == null) {
        return const rd.Failure(
          DropboxFailure(message: 'Falha ao obter token de acesso do Dropbox.'),
        );
      }

      _cachedAccessToken = tokenResponse['access_token'] as String;
      _cachedRefreshToken = tokenResponse['refresh_token'] as String?;

      final expiresIn = tokenResponse['expires_in'] as int?;
      if (expiresIn != null) {
        _tokenExpiration = DateTime.now().add(Duration(seconds: expiresIn));
      }

      final emailResult = await _fetchUserEmail(_cachedAccessToken!);
      if (emailResult.isError()) {
        return rd.Failure(emailResult.exceptionOrNull()!);
      }

      _cachedEmail = emailResult.getOrNull();

      await _saveCredentials(tokenResponse, _cachedEmail!);

      return rd.Success(
        DropboxAuthResult(
          accessToken: _cachedAccessToken!,
          refreshToken: _cachedRefreshToken,
          email: _cachedEmail!,
          expirationDate: _tokenExpiration,
        ),
      );
    } on Object catch (e) {
      return rd.Failure(
        DropboxFailure(message: _parseAuthError(e), originalError: e),
      );
    }
  }

  Future<Map<String, dynamic>?> _getTokenWithExternalBrowser() async {
    HttpServer? server;

    try {
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        AppConstants.oauthLoopbackPort,
      );

      final authUrl = _buildAuthUrl();

      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Não foi possível abrir o navegador');
      }

      final request = await server.first.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw Exception('Tempo limite de autenticação excedido');
        },
      );

      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];
      final errorDescription = request.uri.queryParameters['error_description'];

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_getSuccessHtml(error == null));
      await request.response.close();

      if (error != null) {
        final errorMessage =
            errorDescription != null && errorDescription.isNotEmpty
            ? '$error: $errorDescription'
            : error;
        throw Exception('Erro de autenticação: $errorMessage');
      }

      if (code == null) {
        throw Exception('Código de autorização não recebido');
      }

      final tokenResponse = await _exchangeCodeForToken(code);

      return tokenResponse;
    } finally {
      await server?.close();
    }
  }

  String _buildAuthUrl() {
    const redirectUri = AppConstants.oauthRedirectUri;

    final params = {
      'client_id': _clientId!,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'token_access_type': 'offline',
      'scope': AppConstants.dropboxScopes.join(' '),
    };

    final queryString = params.entries
        .map((e) {
          final encodedKey = Uri.encodeComponent(e.key);
          final encodedValue = Uri.encodeComponent(e.value);
          return '$encodedKey=$encodedValue';
        })
        .join('&');

    return 'https://www.dropbox.com/oauth2/authorize?$queryString';
  }

  Future<Map<String, dynamic>?> _exchangeCodeForToken(String code) async {
    try {
      const redirectUri = AppConstants.oauthRedirectUri;

      final tokenData = {
        'code': code,
        'grant_type': 'authorization_code',
        'client_id': _clientId!,
        'client_secret': _clientSecret ?? '',
        'redirect_uri': redirectUri,
      };

      final response = await _dio!.post(
        '/oauth2/token',
        data: tokenData,
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Falha ao trocar código por token: ${response.statusCode}',
        );
      }

      return response.data as Map<String, dynamic>;
    } on Object catch (e) {
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

  Future<rd.Result<DropboxAuthResult>> signInSilently() async {
    if (!_isInitialized) {
      return const rd.Failure(
        DropboxFailure(message: 'DropboxAuthService não inicializado.'),
      );
    }

    try {
      if (_cachedAccessToken != null && _cachedEmail != null) {
        if (_isTokenExpired()) {
          final refreshResult = await _refreshToken();
          if (refreshResult.isError()) {
            return refreshResult;
          }
        }

        return rd.Success(
          DropboxAuthResult(
            accessToken: _cachedAccessToken!,
            refreshToken: _cachedRefreshToken,
            email: _cachedEmail!,
            expirationDate: _tokenExpiration,
          ),
        );
      }

      return const rd.Failure(
        DropboxFailure(message: 'Nenhuma conta Dropbox autenticada.'),
      );
    } on Object catch (e) {
      return rd.Failure(
        DropboxFailure(
          message: 'Erro ao restaurar sessão: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<DropboxAuthResult>> _refreshToken() async {
    if (_cachedRefreshToken == null) {
      return const rd.Failure(
        DropboxFailure(message: 'Não há refresh token disponível.'),
      );
    }

    try {
      final response = await _dio!.post(
        '/oauth2/token',
        data: {
          'grant_type': 'refresh_token',
          'refresh_token': _cachedRefreshToken,
          'client_id': _clientId,
          'client_secret': _clientSecret ?? '',
        },
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      if (response.statusCode != 200) {
        await _clearStoredCredentials();
        return const rd.Failure(
          DropboxFailure(message: 'Sessão expirada. Faça login novamente.'),
        );
      }

      final data = response.data as Map<String, dynamic>;
      _cachedAccessToken = data['access_token'] as String;
      _cachedRefreshToken =
          data['refresh_token'] as String? ?? _cachedRefreshToken;

      final expiresIn = data['expires_in'] as int?;
      if (expiresIn != null) {
        _tokenExpiration = DateTime.now().add(Duration(seconds: expiresIn));
      }

      await _saveCredentials(data, _cachedEmail!);

      return rd.Success(
        DropboxAuthResult(
          accessToken: _cachedAccessToken!,
          refreshToken: _cachedRefreshToken,
          email: _cachedEmail!,
          expirationDate: _tokenExpiration,
        ),
      );
    } on Object catch (e) {
      await _clearStoredCredentials();
      return rd.Failure(
        DropboxFailure(
          message: 'Falha ao atualizar sessão. Faça login novamente.',
          originalError: e,
        ),
      );
    }
  }

  Future<void> signOut() async {
    await _clearStoredCredentials();

    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _cachedEmail = null;
    _tokenExpiration = null;
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
      final response = await _dio!.post(
        '/2/users/get_current_account',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final email = data['email'] as String?;

        if (email == null || email.isEmpty) {
          return const rd.Failure(
            DropboxFailure(message: 'Email não encontrado na resposta.'),
          );
        }

        return rd.Success(email);
      }

      return rd.Failure(
        DropboxFailure(message: 'Erro ao obter email: ${response.statusCode}'),
      );
    } on Object catch (e) {
      return rd.Failure(
        DropboxFailure(
          message: 'Erro ao obter informações do usuário: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<void> _saveCredentials(
    Map<String, dynamic> tokenResponse,
    String email,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final credentials = {
        'accessToken': tokenResponse['access_token'],
        'refreshToken': tokenResponse['refresh_token'],
        'expirationDate': _tokenExpiration?.toIso8601String(),
      };

      final encryptedData = EncryptionService.encrypt(jsonEncode(credentials));
      await prefs.setString(_storageKey, encryptedData);
      await prefs.setString(_emailStorageKey, email);
    } on Object catch (e) {
      // Ignore save errors
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
    } on Object catch (e) {
      await _clearStoredCredentials();
    }
  }

  Future<void> _clearStoredCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      await prefs.remove(_emailStorageKey);
    } on Object catch (e) {
      // Ignore clear errors
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

    return 'Erro na autenticação Dropbox: $e';
  }

  void setCredentials(
    String accessToken,
    String email, {
    String? refreshToken,
  }) {
    _cachedAccessToken = accessToken;
    _cachedEmail = email;
    _cachedRefreshToken = refreshToken;
  }
}
