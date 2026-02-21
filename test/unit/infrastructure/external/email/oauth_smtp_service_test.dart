import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/email/oauth_smtp_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oauth2_client/access_token_response.dart';
import 'package:oauth2_client/oauth2_client.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockSecureCredentialService extends Mock
    implements ISecureCredentialService {}

void main() {
  late _MockSecureCredentialService secureCredentialService;
  late OAuthSmtpService service;

  setUp(() {
    secureCredentialService = _MockSecureCredentialService();
    service = OAuthSmtpService(secureCredentialService);
  });

  group('OAuthSmtpService', () {
    test('resolveValidAccessToken refreshes and persists new token', () async {
      final expiredAt = DateTime.now()
          .subtract(const Duration(minutes: 2))
          .toUtc()
          .toIso8601String();
      final refreshedAt = DateTime.now()
          .add(const Duration(hours: 1))
          .toUtc()
          .millisecondsSinceEpoch;

      when(
        () => secureCredentialService.getToken(key: 'oauth-token-key'),
      ).thenAnswer(
        (_) async => rd.Success(<String, dynamic>{
          'access_token': 'expired-token',
          'refresh_token': 'refresh-token',
          'expires_at': expiredAt,
          'account_email': 'oauth-user@example.com',
        }),
      );
      when(
        () => secureCredentialService.storeToken(
          key: 'oauth-token-key',
          tokenData: any(named: 'tokenData'),
        ),
      ).thenAnswer((_) async => const rd.Success(unit));

      final service = OAuthSmtpService(
        secureCredentialService,
        googleClientIdOverride: 'google-client-id',
        refreshTokenFn:
            (
              client,
              refreshToken, {
              required clientId,
              required scopes,
              clientSecret,
            }) async {
              expect(refreshToken, 'refresh-token');
              expect(clientId, 'google-client-id');
              return AccessTokenResponse.fromMap({
                'http_status_code': 200,
                'access_token': 'refreshed-access-token',
                'refresh_token': 'new-refresh-token',
                'expiration_date': refreshedAt,
              });
            },
      );

      final result = await service.resolveValidAccessToken(
        provider: SmtpOAuthProvider.google,
        tokenKey: 'oauth-token-key',
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrElse((_) => ''), 'refreshed-access-token');
      verify(
        () => secureCredentialService.storeToken(
          key: 'oauth-token-key',
          tokenData: any(named: 'tokenData'),
        ),
      ).called(1);
    });

    test(
      'resolveValidAccessToken returns cached token when still valid',
      () async {
        final expiresAt = DateTime.now()
            .add(const Duration(minutes: 10))
            .toUtc();
        when(
          () => secureCredentialService.getToken(key: 'oauth-token-key'),
        ).thenAnswer(
          (_) async => rd.Success(<String, dynamic>{
            'access_token': 'cached-access-token',
            'refresh_token': 'cached-refresh-token',
            'expires_at': expiresAt.toIso8601String(),
          }),
        );

        final result = await service.resolveValidAccessToken(
          provider: SmtpOAuthProvider.google,
          tokenKey: 'oauth-token-key',
        );

        expect(result.isSuccess(), isTrue);
        expect(result.getOrElse((_) => ''), 'cached-access-token');
        verify(
          () => secureCredentialService.getToken(key: 'oauth-token-key'),
        ).called(1);
        verifyNever(
          () => secureCredentialService.storeToken(
            key: any(named: 'key'),
            tokenData: any(named: 'tokenData'),
          ),
        );
      },
    );

    test(
      'resolveValidAccessToken fails when token is expired and refresh token is missing',
      () async {
        final expiresAt = DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toUtc();
        when(
          () => secureCredentialService.getToken(key: 'oauth-token-key'),
        ).thenAnswer(
          (_) async => rd.Success(<String, dynamic>{
            'access_token': 'expired-token',
            'expires_at': expiresAt.toIso8601String(),
          }),
        );

        final result = await service.resolveValidAccessToken(
          provider: SmtpOAuthProvider.google,
          tokenKey: 'oauth-token-key',
        );

        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<ServerFailure>());
        expect(
          result.exceptionOrNull().toString().toLowerCase(),
          contains('sessao oauth smtp expirada'),
        );
      },
    );

    test('resolveValidAccessToken propagates secure storage errors', () async {
      when(
        () => secureCredentialService.getToken(key: 'oauth-token-key'),
      ).thenAnswer(
        (_) async => const rd.Failure(
          ServerFailure(message: 'falha ao ler token'),
        ),
      );

      final result = await service.resolveValidAccessToken(
        provider: SmtpOAuthProvider.google,
        tokenKey: 'oauth-token-key',
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ServerFailure>());
      expect(
        result.exceptionOrNull().toString().toLowerCase(),
        contains('falha ao ler token'),
      );
    });

    test('resolveValidAccessToken fails when token key is empty', () async {
      final result = await service.resolveValidAccessToken(
        provider: SmtpOAuthProvider.google,
        tokenKey: '   ',
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ValidationFailure>());
    });

    test('connect fails when provider client id is not configured', () async {
      final result = await service.connect(
        configId: 'cfg-1',
        provider: SmtpOAuthProvider.google,
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ValidationFailure>());
      expect(
        result.exceptionOrNull().toString().toLowerCase(),
        contains('smtp_google_client_id'),
      );
      verifyNever(
        () => secureCredentialService.storeToken(
          key: any(named: 'key'),
          tokenData: any(named: 'tokenData'),
        ),
      );
    });

    test('connect maps consent cancellation errors', () async {
      final service = OAuthSmtpService(
        secureCredentialService,
        googleClientIdOverride: 'google-client-id',
        getTokenWithAuthCodeFlowFn:
            (
              client, {
              required clientId,
              required scopes,
              clientSecret,
            }) async {
              throw Exception('access_denied');
            },
      );

      final result = await service.connect(
        configId: 'cfg-consent',
        provider: SmtpOAuthProvider.google,
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ServerFailure>());
      expect(
        result.exceptionOrNull().toString().toLowerCase(),
        contains('cancelada'),
      );
    });

    test('connect maps network failures during OAuth handshake', () async {
      final service = OAuthSmtpService(
        secureCredentialService,
        googleClientIdOverride: 'google-client-id',
        oauthClientFactory: (_) => OAuth2Client(
          authorizeUrl: 'https://example.com/auth',
          tokenUrl: 'https://example.com/token',
          redirectUri: 'http://localhost:8085/oauth2redirect',
          customUriScheme: 'http://localhost:8085',
        ),
        getTokenWithAuthCodeFlowFn:
            (
              client, {
              required clientId,
              required scopes,
              clientSecret,
            }) async {
              throw const SocketException('network down');
            },
      );

      final result = await service.connect(
        configId: 'cfg-network',
        provider: SmtpOAuthProvider.google,
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ServerFailure>());
      expect(
        result.exceptionOrNull().toString().toLowerCase(),
        contains('falha de rede'),
      );
    });

    test('disconnect delegates token deletion', () async {
      when(
        () => secureCredentialService.deleteToken(key: any(named: 'key')),
      ).thenAnswer((_) async => const rd.Success(unit));

      final result = await service.disconnect(tokenKey: 'oauth-token-key');

      expect(result.isSuccess(), isTrue);
      verify(
        () => secureCredentialService.deleteToken(key: 'oauth-token-key'),
      ).called(1);
    });

    test('disconnect ignores blank token key', () async {
      final result = await service.disconnect(tokenKey: '   ');

      expect(result.isSuccess(), isTrue);
      verifyNever(
        () => secureCredentialService.deleteToken(key: any(named: 'key')),
      );
    });
  });
}
