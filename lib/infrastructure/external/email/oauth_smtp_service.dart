import 'dart:async';
import 'dart:convert';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/smtp_oauth_state.dart';
import 'package:backup_database/domain/services/i_oauth_smtp_service.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2_client/access_token_response.dart';
import 'package:oauth2_client/google_oauth2_client.dart';
import 'package:oauth2_client/microsoft_oauth2_client.dart';
import 'package:oauth2_client/oauth2_client.dart';
import 'package:result_dart/result_dart.dart' as rd;

typedef OAuthTokenExchangeFn =
    Future<AccessTokenResponse> Function(
      OAuth2Client client, {
      required String clientId,
      required List<String> scopes,
      String? clientSecret,
    });

typedef OAuthTokenRefreshFn =
    Future<AccessTokenResponse> Function(
      OAuth2Client client,
      String refreshToken, {
      required String clientId,
      required List<String> scopes,
      String? clientSecret,
    });

typedef OAuthAccountEmailResolver =
    Future<rd.Result<String>> Function({
      required SmtpOAuthProvider provider,
      required String accessToken,
    });

class _FlightLock<T> {
  _FlightLock(this.completer);

  final Completer<T> completer;
}

class OAuthSmtpService implements IOAuthSmtpService {
  OAuthSmtpService(
    this._secureCredentialService, {
    String? googleClientIdOverride,
    String? googleClientSecretOverride,
    String? microsoftClientIdOverride,
    String? microsoftClientSecretOverride,
    String? microsoftTenantOverride,
    OAuth2Client Function(SmtpOAuthProvider provider)? oauthClientFactory,
    OAuthTokenExchangeFn? getTokenWithAuthCodeFlowFn,
    OAuthTokenRefreshFn? refreshTokenFn,
    OAuthAccountEmailResolver? accountEmailResolver,
  }) : _googleClientIdOverride = googleClientIdOverride,
       _googleClientSecretOverride = googleClientSecretOverride,
       _microsoftClientIdOverride = microsoftClientIdOverride,
       _microsoftClientSecretOverride = microsoftClientSecretOverride,
       _microsoftTenantOverride = microsoftTenantOverride,
       _oauthClientFactory = oauthClientFactory,
       _getTokenWithAuthCodeFlowFn = getTokenWithAuthCodeFlowFn,
       _refreshTokenFn = refreshTokenFn,
       _accountEmailResolver = accountEmailResolver;

  static const String _tokenAccessToken = 'access_token';
  static const String _tokenRefreshToken = 'refresh_token';
  static const String _tokenExpiresAt = 'expires_at';
  static const String _tokenAccountEmail = 'account_email';
  static const String _tokenProvider = 'provider';

  final ISecureCredentialService _secureCredentialService;
  final String? _googleClientIdOverride;
  final String? _googleClientSecretOverride;
  final String? _microsoftClientIdOverride;
  final String? _microsoftClientSecretOverride;
  final String? _microsoftTenantOverride;
  final OAuth2Client Function(SmtpOAuthProvider provider)? _oauthClientFactory;
  final OAuthTokenExchangeFn? _getTokenWithAuthCodeFlowFn;
  final OAuthTokenRefreshFn? _refreshTokenFn;
  final OAuthAccountEmailResolver? _accountEmailResolver;
  final Map<String, _FlightLock<rd.Result<String>>> _tokenRefreshLocks = {};

  @override
  Future<rd.Result<SmtpOAuthState>> connect({
    required String configId,
    required SmtpOAuthProvider provider,
  }) async {
    return _connectInternal(
      configId: configId,
      provider: provider,
      clearPrevious: false,
    );
  }

  @override
  Future<rd.Result<SmtpOAuthState>> reconnect({
    required String configId,
    required SmtpOAuthProvider provider,
  }) async {
    return _connectInternal(
      configId: configId,
      provider: provider,
      clearPrevious: true,
    );
  }

  @override
  Future<rd.Result<void>> disconnect({
    required String tokenKey,
  }) async {
    final trimmedKey = tokenKey.trim();
    if (trimmedKey.isEmpty) {
      return const rd.Success(unit);
    }

    final result = await _secureCredentialService.deleteToken(key: trimmedKey);
    if (result.isError()) {
      return rd.Failure(result.exceptionOrNull()!);
    }
    return const rd.Success(unit);
  }

  @override
  Future<rd.Result<String>> resolveValidAccessToken({
    required SmtpOAuthProvider provider,
    required String tokenKey,
  }) async {
    final trimmedKey = tokenKey.trim();
    if (trimmedKey.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Token OAuth SMTP nao configurado'),
      );
    }

    final tokenResult = await _secureCredentialService.getToken(
      key: trimmedKey,
    );
    if (tokenResult.isError()) {
      return rd.Failure(tokenResult.exceptionOrNull()!);
    }

    final tokenData = tokenResult.getOrElse((_) => <String, dynamic>{});
    final accessToken = (tokenData[_tokenAccessToken] as String?)?.trim() ?? '';
    final refreshToken =
        (tokenData[_tokenRefreshToken] as String?)?.trim() ?? '';
    final expiresAtRaw = (tokenData[_tokenExpiresAt] as String?)?.trim();
    final expiresAt = expiresAtRaw == null || expiresAtRaw.isEmpty
        ? null
        : DateTime.tryParse(expiresAtRaw);

    if (accessToken.isNotEmpty &&
        (expiresAt == null ||
            DateTime.now().isBefore(
              expiresAt.subtract(const Duration(minutes: 2)),
            ))) {
      return rd.Success(accessToken);
    }

    if (refreshToken.isEmpty) {
      return const rd.Failure(
        ServerFailure(
          message: 'Sessao OAuth SMTP expirada. Reconecte a conta no modal.',
        ),
      );
    }

    final authConfigResult = _resolveAuthConfig(provider);
    if (authConfigResult.isError()) {
      return rd.Failure(authConfigResult.exceptionOrNull()!);
    }
    final cfg = authConfigResult.getOrElse((_) => throw StateError(''));
    final client =
        _oauthClientFactory?.call(provider) ?? _buildOAuthClient(provider);

    final existingLock = _tokenRefreshLocks[trimmedKey];
    if (existingLock != null) {
      LoggerService.info(
        '[OAuthSmtpService] Token refresh em andamento para tokenKey=$trimmedKey. Aguardando resultado...',
      );
      return existingLock.completer.future;
    }

    final lock = _FlightLock<rd.Result<String>>(Completer<rd.Result<String>>());
    _tokenRefreshLocks[trimmedKey] = lock;

    rd.Result<String>? result;

    try {
      final response = _refreshTokenFn == null
          ? await client.refreshToken(
              refreshToken,
              clientId: cfg.clientId,
              clientSecret: cfg.clientSecret?.isEmpty ?? true
                  ? null
                  : cfg.clientSecret,
              scopes: cfg.scopes,
            )
          : await _refreshTokenFn(
              client,
              refreshToken,
              clientId: cfg.clientId,
              clientSecret: cfg.clientSecret?.isEmpty ?? true
                  ? null
                  : cfg.clientSecret,
              scopes: cfg.scopes,
            );

      final refreshedAccessToken = response.accessToken?.trim() ?? '';
      if (refreshedAccessToken.isEmpty) {
        return const rd.Failure(
          ServerFailure(
            message: 'Falha ao atualizar token OAuth SMTP. Reconecte a conta.',
          ),
        );
      }

      final refreshedTokenData = <String, dynamic>{
        _tokenAccessToken: refreshedAccessToken,
        _tokenRefreshToken: (response.refreshToken?.trim().isNotEmpty ?? false)
            ? response.refreshToken!.trim()
            : refreshToken,
        _tokenExpiresAt: response.expirationDate?.toUtc().toIso8601String(),
        _tokenAccountEmail: tokenData[_tokenAccountEmail],
        _tokenProvider: provider.value,
      };

      final saveResult = await _secureCredentialService.storeToken(
        key: trimmedKey,
        tokenData: refreshedTokenData,
      );
      if (saveResult.isError()) {
        result = rd.Failure(saveResult.exceptionOrNull()!);
      } else {
        result = rd.Success(refreshedAccessToken);
      }
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        '[OAuthSmtpService] Falha ao atualizar token OAuth SMTP',
        e,
        stackTrace,
      );
      result = const rd.Failure(
        ServerFailure(
          message:
              'Falha ao atualizar token OAuth SMTP. Reconecte a conta e tente novamente.',
        ),
      );
    } finally {
      lock.completer.complete(result!);
      _tokenRefreshLocks.remove(trimmedKey);
    }
    return lock.completer.future;
  }

  Future<rd.Result<SmtpOAuthState>> _connectInternal({
    required String configId,
    required SmtpOAuthProvider provider,
    required bool clearPrevious,
  }) async {
    final normalizedConfigId = configId.trim();
    if (normalizedConfigId.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'ID da configuracao SMTP nao informado'),
      );
    }

    final authConfigResult = _resolveAuthConfig(provider);
    if (authConfigResult.isError()) {
      return rd.Failure(authConfigResult.exceptionOrNull()!);
    }
    final cfg = authConfigResult.getOrElse((_) => throw StateError(''));

    final tokenKey = _buildTokenKey(normalizedConfigId, provider);
    if (clearPrevious) {
      await _secureCredentialService.deleteToken(key: tokenKey);
    }

    final client =
        _oauthClientFactory?.call(provider) ?? _buildOAuthClient(provider);
    try {
      final tokenResponse = _getTokenWithAuthCodeFlowFn == null
          ? await client.getTokenWithAuthCodeFlow(
              clientId: cfg.clientId,
              clientSecret: cfg.clientSecret?.isEmpty ?? true
                  ? null
                  : cfg.clientSecret,
              scopes: cfg.scopes,
            )
          : await _getTokenWithAuthCodeFlowFn(
              client,
              clientId: cfg.clientId,
              clientSecret: cfg.clientSecret?.isEmpty ?? true
                  ? null
                  : cfg.clientSecret,
              scopes: cfg.scopes,
            );

      final accessToken = tokenResponse.accessToken?.trim() ?? '';
      if (accessToken.isEmpty) {
        return const rd.Failure(
          ServerFailure(
            message: 'Falha ao autenticar no provedor OAuth SMTP.',
          ),
        );
      }

      final accountResolver = _accountEmailResolver ?? _fetchAccountEmail;
      final accountResult = await accountResolver(
        provider: provider,
        accessToken: accessToken,
      );
      if (accountResult.isError()) {
        return rd.Failure(accountResult.exceptionOrNull()!);
      }

      final accountEmail = accountResult.getOrElse((_) => '');
      final tokenData = <String, dynamic>{
        _tokenAccessToken: accessToken,
        _tokenRefreshToken: tokenResponse.refreshToken?.trim(),
        _tokenExpiresAt: tokenResponse.expirationDate
            ?.toUtc()
            .toIso8601String(),
        _tokenAccountEmail: accountEmail,
        _tokenProvider: provider.value,
      };

      final saveResult = await _secureCredentialService.storeToken(
        key: tokenKey,
        tokenData: tokenData,
      );
      if (saveResult.isError()) {
        return rd.Failure(saveResult.exceptionOrNull()!);
      }

      final now = DateTime.now().toUtc();
      return rd.Success(
        SmtpOAuthState(
          provider: provider,
          accountEmail: accountEmail,
          tokenKey: tokenKey,
          connectedAt: now,
        ),
      );
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        '[OAuthSmtpService] Falha ao conectar OAuth SMTP',
        e,
        stackTrace,
      );
      return rd.Failure(
        ServerFailure(message: _mapOAuthError(e)),
      );
    }
  }

  OAuth2Client _buildOAuthClient(SmtpOAuthProvider provider) {
    switch (provider) {
      case SmtpOAuthProvider.google:
        return GoogleOAuth2Client(
          redirectUri: AppConstants.oauthRedirectUri,
          customUriScheme: 'http://localhost:${AppConstants.oauthLoopbackPort}',
        );
      case SmtpOAuthProvider.microsoft:
        final tenant = (_microsoftTenantOverride?.trim().isNotEmpty ?? false)
            ? _microsoftTenantOverride!.trim()
            : AppConstants.smtpMicrosoftTenant;
        return MicrosoftOauth2Client(
          tenant: tenant,
          redirectUri: AppConstants.oauthRedirectUri,
          customUriScheme: 'http://localhost:${AppConstants.oauthLoopbackPort}',
        );
    }
  }

  Future<rd.Result<String>> _fetchAccountEmail({
    required SmtpOAuthProvider provider,
    required String accessToken,
  }) async {
    final uri = switch (provider) {
      SmtpOAuthProvider.google => Uri.parse(
        'https://www.googleapis.com/oauth2/v2/userinfo',
      ),
      SmtpOAuthProvider.microsoft => Uri.parse(
        'https://graph.microsoft.com/v1.0/me',
      ),
    };

    try {
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return rd.Failure(
          ServerFailure(
            message:
                'Nao foi possivel obter e-mail da conta OAuth (${response.statusCode}).',
          ),
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final email = _extractEmailFromProfile(provider, payload);
      if (email == null || email.trim().isEmpty) {
        return const rd.Failure(
          ServerFailure(
            message: 'Nao foi possivel identificar o e-mail da conta OAuth.',
          ),
        );
      }

      return rd.Success(email.trim());
    } on Object catch (e) {
      return rd.Failure(
        ServerFailure(
          message: 'Falha ao consultar perfil da conta OAuth: $e',
        ),
      );
    }
  }

  String? _extractEmailFromProfile(
    SmtpOAuthProvider provider,
    Map<String, dynamic> payload,
  ) {
    if (provider == SmtpOAuthProvider.google) {
      return payload['email'] as String?;
    }

    return payload['mail'] as String? ??
        payload['userPrincipalName'] as String?;
  }

  rd.Result<_OAuthClientConfig> _resolveAuthConfig(SmtpOAuthProvider provider) {
    final googleClientId =
        (_googleClientIdOverride ?? AppConstants.smtpGoogleClientId).trim();
    final googleClientSecret =
        (_googleClientSecretOverride ?? AppConstants.smtpGoogleClientSecret)
            .trim();
    final microsoftClientId =
        (_microsoftClientIdOverride ?? AppConstants.smtpMicrosoftClientId)
            .trim();
    final microsoftClientSecret =
        (_microsoftClientSecretOverride ??
                AppConstants.smtpMicrosoftClientSecret)
            .trim();

    switch (provider) {
      case SmtpOAuthProvider.google:
        if (!AppConstants.enableGoogleSmtpOAuth) {
          return const rd.Failure(
            ValidationFailure(
              message: 'OAuth SMTP Google desabilitado por feature flag.',
            ),
          );
        }
        if (googleClientId.isEmpty) {
          return const rd.Failure(
            ValidationFailure(
              message:
                  'SMTP_GOOGLE_CLIENT_ID nao configurado. Defina a credencial OAuth para Google SMTP.',
            ),
          );
        }
        return rd.Success(
          _OAuthClientConfig(
            clientId: googleClientId,
            clientSecret: googleClientSecret,
            scopes: AppConstants.smtpGoogleScopes,
          ),
        );
      case SmtpOAuthProvider.microsoft:
        if (!AppConstants.enableMicrosoftSmtpOAuth) {
          return const rd.Failure(
            ValidationFailure(
              message: 'OAuth SMTP Microsoft desabilitado por feature flag.',
            ),
          );
        }
        if (microsoftClientId.isEmpty) {
          return const rd.Failure(
            ValidationFailure(
              message:
                  'SMTP_MICROSOFT_CLIENT_ID nao configurado. Defina a credencial OAuth para Microsoft SMTP.',
            ),
          );
        }
        return rd.Success(
          _OAuthClientConfig(
            clientId: microsoftClientId,
            clientSecret: microsoftClientSecret,
            scopes: AppConstants.smtpMicrosoftScopes,
          ),
        );
    }
  }

  String _buildTokenKey(String configId, SmtpOAuthProvider provider) {
    return 'email_smtp_oauth_token_${provider.value}_$configId';
  }

  String _mapOAuthError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('access_denied') || text.contains('cancel')) {
      return 'Autenticacao OAuth cancelada pelo usuario.';
    }
    if (text.contains('invalid_client')) {
      return 'Credenciais OAuth invalidas para SMTP.';
    }
    if (text.contains('network') || text.contains('socket')) {
      return 'Falha de rede durante autenticacao OAuth SMTP.';
    }
    if (text.contains('timeout')) {
      return 'Tempo limite excedido na autenticacao OAuth SMTP.';
    }
    return 'Falha ao autenticar conta OAuth SMTP: $error';
  }
}

class _OAuthClientConfig {
  const _OAuthClientConfig({
    required this.clientId,
    required this.clientSecret,
    required this.scopes,
  });

  final String clientId;
  final String? clientSecret;
  final List<String> scopes;
}
