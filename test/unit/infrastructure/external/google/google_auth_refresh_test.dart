import 'dart:async';
import 'dart:convert';

import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_auth_client.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oauth2_client/access_token_response.dart';
import 'package:result_dart/result_dart.dart' hide unit;

class _Store extends Mock implements ISecureCredentialService {}

void main() {
  late _Store store;
  late Map<String, dynamic> saved;
  late int requests;
  late int status;
  late MockClient client;

  setUp(() {
    store = _Store();
    saved = {
      'accessToken': 'old',
      'refreshToken': 'refresh',
      'email': 'user@example.com',
      'expirationDate': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
    };
    requests = 0;
    when(() => store.deleteToken(key: any(named: 'key'))).thenAnswer((_) async {
      saved = {};
      return const Success(unit);
    });
    status = 200;
    when(() => store.getToken(key: any(named: 'key')))
        .thenAnswer((_) async => Success(Map<String, dynamic>.of(saved)));
    when(
      () => store.storeToken(
        key: any(named: 'key'),
        tokenData: any(named: 'tokenData'),
      ),
    ).thenAnswer((call) async {
      saved = call.namedArguments[#tokenData] as Map<String, dynamic>;
      return const Success(unit);
    });
    client = MockClient((request) async {
      requests++;
      expect(request.url.toString(), 'https://oauth2.googleapis.com/token');
      expect(request.bodyFields['grant_type'], 'refresh_token');
      expect(request.bodyFields['refresh_token'], 'refresh');
      expect(request.bodyFields['client_id'], 'client');
      return http.Response(
        jsonEncode(
          status == 200
              ? {
                  'access_token': 'new',
                  'expires_in': 3600,
                  'token_type': 'Bearer',
                }
              : {'error': status == 400 ? 'invalid_grant' : 'server_error'},
        ),
        status,
      );
    });
    addTearDown(client.close);
  });

  Future<GoogleAuthService> create() async {
    final service = GoogleAuthService(store, httpClient: client);
    await service.initialize(clientId: 'client');
    return service;
  }

  test(
    'expired token renews silently and survives application restart',
    () async {
      final result = await (await create()).signInSilently();
      expect(result.getOrThrow().accessToken, 'new');
      expect(saved['refreshToken'], 'refresh');
      expect(
        DateTime.parse(saved['expirationDate'] as String)
            .difference(DateTime.now())
            .inMinutes,
        inInclusiveRange(59, 60),
      );
      expect((await (await create()).signInSilently()).isSuccess(), isTrue);
      expect(requests, 1);
    },
  );

  test('legacy token without expiration is renewed', () async {
    saved.remove('expirationDate');
    expect((await (await create()).signInSilently()).isSuccess(), isTrue);
    expect(requests, 1);
  });

  test('login blocks renewal and cannot complete after logout', () async {
    final authorization = Completer<AccessTokenResponse?>();
    final transport = MockClient(
      (_) async => http.Response('{"email":"new@example.com"}', 200),
    );
    addTearDown(transport.close);
    final service = GoogleAuthService(
      store,
      httpClient: transport,
      authorize: () => authorization.future,
    );
    await service.initialize(clientId: 'client');
    final login = service.signIn();
    expect((await service.signInSilently()).isError(), isTrue);
    expect((await service.signIn()).isError(), isTrue);
    await service.signOut();
    authorization.complete(
      AccessTokenResponse.fromHttpResponse(
        http.Response(
          '{"access_token":"late","refresh_token":"late-refresh","expires_in":3600}',
          200,
        ),
      ),
    );
    expect((await login).isError(), isTrue);
    expect(service.isSignedIn, isFalse);
    expect(saved, isEmpty);
  });

  test('rotated refresh token is persisted for restart', () async {
    final transport = MockClient(
      (_) async => http.Response(
        '{"access_token":"rotated","refresh_token":"rotated-refresh","expires_in":3600}',
        200,
      ),
    );
    addTearDown(transport.close);
    final service = GoogleAuthService(store, httpClient: transport);
    await service.initialize(clientId: 'client');
    expect((await service.signInSilently()).isSuccess(), isTrue);
    expect(saved['refreshToken'], 'rotated-refresh');
    expect(
      (await (await create()).signInSilently()).getOrThrow().refreshToken,
      'rotated-refresh',
    );
  });

  for (final scenario in [
    'email-failure',
    'storage-failure',
    'missing-refresh',
    'success',
  ]) {
    test(
      'interactive login commits credentials atomically: $scenario',
      () async {
        final transport = MockClient(
          (_) async => http.Response(
            scenario == 'email-failure'
                ? 'unavailable'
                : '{"email":"new@example.com"}',
            scenario == 'email-failure' ? 503 : 200,
          ),
        );
        addTearDown(transport.close);
        if (scenario == 'storage-failure') {
          when(
            () => store.storeToken(
              key: any(named: 'key'),
              tokenData: any(named: 'tokenData'),
            ),
          ).thenAnswer((_) async => Failure(Exception('disk unavailable')));
        }
        final service = GoogleAuthService(
          store,
          httpClient: transport,
          authorize: () async => AccessTokenResponse.fromHttpResponse(
            http.Response(
              jsonEncode({
                'access_token': 'new-login',
                'expires_in': 3600,
                if (scenario != 'missing-refresh')
                  'refresh_token': 'new-refresh',
              }),
              200,
            ),
          ),
        );
        await service.initialize(clientId: 'client');
        final result = await service.signIn();
        expect(result.isSuccess(), scenario == 'success');
        expect(
          service.accessToken,
          scenario == 'success' ? 'new-login' : 'old',
        );
        expect(
          service.currentUserEmail,
          scenario == 'success' ? 'new@example.com' : 'user@example.com',
        );
        expect(
          saved['refreshToken'],
          scenario == 'success' ? 'new-refresh' : 'refresh',
        );
        expect((await create()).currentUserEmail, service.currentUserEmail);
      },
    );
  }

  test(
    'invalid legacy expiration renews without erasing refresh token',
    () async {
      saved['expirationDate'] = 'invalid';
      expect((await (await create()).signInSilently()).isSuccess(), isTrue);
      expect(saved['refreshToken'], 'refresh');
    },
  );

  test('credentials bound to another client are not used', () async {
    saved['clientId'] = 'another-client';
    expect((await (await create()).signInSilently()).isError(), isTrue);
    expect(requests, 0);
    expect(saved['refreshToken'], 'refresh');
  });

  for (final body in [
    '<html>Proxy error</html>',
    '{"access_token":"", "expires_in":3600}',
    '{"access_token":"new"}',
    '{"access_token":"new", "expires_in":0}',
  ]) {
    test('malformed response preserves credentials: $body', () async {
      final transport = MockClient((_) async => http.Response(body, 200));
      addTearDown(transport.close);
      final service = GoogleAuthService(store, httpClient: transport);
      await service.initialize(clientId: 'client');
      expect((await service.signInSilently()).isError(), isTrue);
      expect(saved['accessToken'], 'old');
      expect(saved['refreshToken'], 'refresh');
    });
  }

  test('late network response cannot restore signed-out session', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final transport = MockClient((_) {
      started.complete();
      return response.future;
    });
    addTearDown(transport.close);
    final service = GoogleAuthService(store, httpClient: transport);
    await service.initialize(clientId: 'client');
    final refresh = service.signInSilently();
    await started.future;
    await service.signOut();
    response.complete(
      http.Response('{"access_token":"late","expires_in":3600}', 200),
    );
    expect((await refresh).isError(), isTrue);
    expect(service.isSignedIn, isFalse);
    expect(saved, isEmpty);
  });

  test('logout waits for in-flight persistence then removes it', () async {
    final writing = Completer<void>();
    final release = Completer<void>();
    when(
      () => store.storeToken(
        key: any(named: 'key'),
        tokenData: any(named: 'tokenData'),
      ),
    ).thenAnswer((call) async {
      writing.complete();
      await release.future;
      saved = call.namedArguments[#tokenData] as Map<String, dynamic>;
      return const Success(unit);
    });
    final service = await create();
    final refresh = service.signInSilently();
    await writing.future;
    final logout = service.signOut();
    release.complete();
    await logout;
    expect((await refresh).isError(), isTrue);
    expect(saved, isEmpty);
    expect((await create()).isSignedIn, isFalse);
  });

  test(
    'delete failure is reported instead of claiming durable logout',
    () async {
      when(() => store.deleteToken(key: any(named: 'key')))
          .thenAnswer((_) async => Failure(Exception('disk unavailable')));
      final service = await create();
      await expectLater(service.signOut(), throwsStateError);
      expect(service.isSignedIn, isFalse);
    },
  );

  test('timeout and late response preserve stored credentials', () async {
    final response = Completer<http.Response>();
    final transport = MockClient((_) => response.future);
    addTearDown(transport.close);
    final service = GoogleAuthService(
      store,
      httpClient: transport,
      requestTimeout: const Duration(milliseconds: 10),
    );
    await service.initialize(clientId: 'client');
    expect((await service.signInSilently()).isError(), isTrue);
    response.complete(
      http.Response('{"access_token":"late","expires_in":3600}', 200),
    );
    await Future<void>.delayed(Duration.zero);
    expect(saved['accessToken'], 'old');
    expect((await (await create()).signInSilently()).isSuccess(), isTrue);
  });

  test(
    'storage failure does not publish an unpersisted renewed token',
    () async {
      when(
        () => store.storeToken(
          key: any(named: 'key'),
          tokenData: any(named: 'tokenData'),
        ),
      ).thenAnswer((_) async => Failure(Exception('disk unavailable')));
      final service = await create();
      expect((await service.signInSilently()).isError(), isTrue);
      expect(service.accessToken, 'old');
      expect(saved['refreshToken'], 'refresh');
    },
  );

  test('concurrent renewal uses one refresh request', () async {
    final service = await create();
    final results = await Future.wait(
      List.generate(5, (_) => service.signInSilently()),
    );
    expect(results.every((result) => result.isSuccess()), isTrue);
    expect(requests, 1);
  });

  test('temporary failure preserves credentials and allows retry', () async {
    final service = await create();
    status = 503;
    expect((await service.signInSilently()).isError(), isTrue);
    expect(saved['refreshToken'], 'refresh');
    verifyNever(() => store.deleteToken(key: any(named: 'key')));
    status = 200;
    expect((await service.signInSilently()).isSuccess(), isTrue);
  });

  test('revoked grant explains when a new login is required', () async {
    status = 400;
    final result = await (await create()).signInSilently();
    expect(
      result.exceptionOrNull().toString(),
      contains('Faça login novamente'),
    );
  });

  test('401 forces renewal even before recorded expiration', () async {
    saved['expirationDate'] = DateTime.now()
        .add(const Duration(hours: 1))
        .toIso8601String();
    final auth = GoogleDriveAuthClient(await create());
    var attempts = 0;
    final token = await auth.executeWithTokenRefresh(() async {
      if (attempts++ == 0) {
        throw drive.DetailedApiRequestError(401, 'Unauthorized');
      }
      final session = (await auth.getAuthenticatedClient()).getOrThrow();
      addTearDown(session.client.close);
      return session.accessToken;
    });
    expect(token, 'new');
    expect(requests, 1);
  });
}
