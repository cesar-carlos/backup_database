import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/providers/google_auth_provider.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';
import 'package:backup_database/infrastructure/external/google/google_oauth_config_store.dart';
import 'package:backup_database/infrastructure/external/oauth/oauth_session_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oauth2_client/access_token_response.dart';
import 'package:result_dart/result_dart.dart' hide unit;
import 'package:shared_preferences/shared_preferences.dart';

class _Credentials extends Mock implements ISecureCredentialService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Credentials credentials;
  late Map<String, Map<String, dynamic>> values;
  late GoogleOAuthConfigStore config;
  late MockClient client;
  late int renewals;
  late Directory lockDirectory;
  const configKey = GoogleOAuthConfigStore.key;
  setUp(() async {
    lockDirectory = await Directory.systemTemp.createTemp(
      'google-session-test-',
    );
    SharedPreferences.setMockInitialValues({});
    EncryptionService.initializeWithDeviceKey('headless-test');
    credentials = _Credentials();
    values = {
      configKey: {'clientId': 'client', 'clientSecret': 'secret'},
      'google_oauth_token': {
        'clientId': 'client',
        'accessToken': 'old',
        'refreshToken': 'refresh',
        'email': 'user@example.com',
        'expirationDate': '2020-01-01T00:00:00Z',
      },
    };
    when(() => credentials.containsKey(key: any(named: 'key'))).thenAnswer(
      (call) async => Success(values.containsKey(call.namedArguments[#key])),
    );
    when(() => credentials.getToken(key: any(named: 'key'))).thenAnswer(
      (call) async => Success(
        Map<String, dynamic>.of(values[call.namedArguments[#key]] ?? {}),
      ),
    );
    when(
      () => credentials.storeToken(
        key: any(named: 'key'),
        tokenData: any(named: 'tokenData'),
      ),
    ).thenAnswer((call) async {
      values[call.namedArguments[#key] as String] = Map<String, dynamic>.of(
        call.namedArguments[#tokenData] as Map<String, dynamic>,
      );
      return const Success(unit);
    });
    when(() => credentials.deleteToken(key: any(named: 'key')))
        .thenAnswer((call) async {
          values.remove(call.namedArguments[#key]);
          return const Success(unit);
        });
    config = GoogleOAuthConfigStore(credentials);
    renewals = 0;
    client = MockClient((request) async {
      renewals++;
      expect(request.bodyFields['client_id'], 'client');
      expect(request.bodyFields['client_secret'], 'secret');
      return http.Response(
        '{"access_token":"fresh","expires_in":3600,"token_type":"Bearer"}',
        200,
      );
    });
  });
  tearDown(() async {
    client.close();
    await lockDirectory.delete(recursive: true);
    EncryptionService.resetToLegacy();
  });

  GoogleAuthService executor() => GoogleAuthService(
    credentials,
    configurationStore: config,
    httpClient: client,
    sessionLock: OAuthSessionLock(
      directory: lockDirectory,
      fileName: 'google-session.lock',
    ),
    authorize: () => throw StateError('Headless must not open a browser'),
  );

  for (final responseLost in [false, true]) {
    test(
      'should retain logout lock after caller timeout until marker settles, responseLost=$responseLost',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        var browserOpened = false;
        when(
          () => credentials.storeToken(
            key: 'google_oauth_token',
            tokenData: any(named: 'tokenData'),
          ),
        ).thenAnswer((call) async {
          final data = Map<String, dynamic>.of(
            call.namedArguments[#tokenData] as Map<String, dynamic>,
          );
          if (data['signedOut'] == true) {
            entered.complete();
            await release.future;
          }
          values['google_oauth_token'] = data;
          if (responseLost && data['signedOut'] == true) {
            return Failure(Exception('write acknowledgement lost'));
          }
          return const Success(unit);
        });
        final transport = MockClient(
          (_) async => http.Response('{"email":"new@example.com"}', 200),
        );
        addTearDown(transport.close);
        final ui = GoogleAuthService(
          credentials,
          configurationStore: config,
          httpClient: transport,
          sessionLock: OAuthSessionLock(
            directory: lockDirectory,
            fileName: 'google-session.lock',
          ),
          authorize: () async {
            browserOpened = true;
            return AccessTokenResponse.fromHttpResponse(
              http.Response(
                jsonEncode({
                  'access_token': 'new-login',
                  'refresh_token': 'new-refresh',
                  'expires_in': 3600,
                  'token_type': 'Bearer',
                }),
                200,
              ),
            );
          },
        );
        await ui.initialize(clientId: 'client', clientSecret: 'secret');
        final logout = executor().signOut();
        await entered.future;
        await expectLater(
          logout.timeout(const Duration(milliseconds: 30)),
          throwsA(isA<TimeoutException>()),
        );
        final login = ui.signIn();
        try {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(browserOpened, isFalse);
        } finally {
          release.complete();
          await logout;
        }
        expect((await login).isSuccess(), isTrue);
        expect(values['google_oauth_token']!['accessToken'], 'new-login');
        expect(
          (await executor().signInSilently()).getOrThrow().accessToken,
          'new-login',
        );
      },
    );
  }

  test(
    'should time out logout behind pending persistence and recover after retry',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var writes = 0;
      when(
        () => credentials.storeToken(
          key: 'google_oauth_token',
          tokenData: any(named: 'tokenData'),
        ),
      ).thenAnswer((call) async {
        if (writes++ == 0) {
          entered.complete();
          await release.future;
        }
        values['google_oauth_token'] = Map<String, dynamic>.of(
          call.namedArguments[#tokenData] as Map<String, dynamic>,
        );
        return const Success(unit);
      });
      final auth = GoogleAuthService(
        credentials,
        configurationStore: config,
        httpClient: client,
        sessionLock: OAuthSessionLock(
          directory: lockDirectory,
          fileName: 'google-session.lock',
          acquisitionTimeout: const Duration(milliseconds: 100),
        ),
      );
      final renewal = auth.signInSilently();
      await entered.future;
      try {
        await expectLater(
          auth.signOut().timeout(const Duration(seconds: 2)),
          throwsA(
            isA<TimeoutException>().having(
              (e) => e.message,
              'lock timeout',
              contains('OAuth'),
            ),
          ),
        );
      } finally {
        release.complete();
        await renewal;
      }
      expect(auth.accessToken, isNull);
      expect(writes, 1);
      expect(values['google_oauth_token']!['signedOut'], isNull);
      await executor().signOut();
      expect((await executor().signInSilently()).isError(), isTrue);
      expect(values['google_oauth_token']!['signedOut'], isTrue);
    },
  );

  for (final partialWriteFailure in [false, true]) {
    test(
      'should complete login after same-session renewal, partial write=$partialWriteFailure',
      () async {
        await executor().signInSilently();
        final previousSession = values['google_oauth_token']!['sessionId'];
        values['google_oauth_token']!['accessToken'] = 'before-renewal';
        final authorization = Completer<AccessTokenResponse?>();
        final entered = Completer<void>();
        final transport = MockClient(
          (_) async => http.Response('{"email":"new@example.test"}', 200),
        );
        addTearDown(transport.close);
        final ui = GoogleAuthService(
          credentials,
          configurationStore: config,
          httpClient: transport,
          sessionLock: OAuthSessionLock(
            directory: lockDirectory,
            fileName: 'google-session.lock',
          ),
          authorize: () {
            entered.complete();
            return authorization.future;
          },
        );
        await ui.initialize(clientId: 'client', clientSecret: 'secret');
        final login = ui.signIn();
        await entered.future;
        if (partialWriteFailure) {
          when(
            () => credentials.storeToken(
              key: any(named: 'key'),
              tokenData: any(named: 'tokenData'),
            ),
          ).thenAnswer((call) async {
            values[call.namedArguments[#key]
                as String] = Map<String, dynamic>.of(
              call.namedArguments[#tokenData] as Map<String, dynamic>,
            );
            return Failure(Exception('legacy cleanup failed after commit'));
          });
        }
        expect(
          (await executor().signInSilently(forceRefresh: true)).isSuccess(),
          isTrue,
        );
        expect(values['google_oauth_token']!['sessionId'], previousSession);
        authorization.complete(
          AccessTokenResponse.fromHttpResponse(
            http.Response(
              '{"access_token":"new-login","refresh_token":"new-refresh","expires_in":3600,"token_type":"Bearer"}',
              200,
            ),
          ),
        );
        expect((await login).getOrThrow().accessToken, 'new-login');
        expect(
          values['google_oauth_token']!['sessionId'],
          isNot(previousSession),
        );
        expect(
          (await executor().signInSilently()).getOrThrow().accessToken,
          'new-login',
        );
      },
    );
  }

  for (final logoutFails in [false, true]) {
    test(
      'should not open browser after logout during credential read, failure=$logoutFails',
      () async {
        var browserCalls = 0;
        final service = GoogleAuthService(
          credentials,
          configurationStore: config,
          httpClient: client,
          sessionLock: OAuthSessionLock(
            directory: lockDirectory,
            fileName: 'google-session.lock',
          ),
          authorize: () async {
            browserCalls++;
            return null;
          },
        );
        await service.initialize(clientId: 'client', clientSecret: 'secret');
        final entered = Completer<void>();
        final release = Completer<void>();
        var reads = 0;
        when(() => credentials.getToken(key: 'google_oauth_token'))
            .thenAnswer((_) async {
              final snapshot = Map<String, dynamic>.of(
                values['google_oauth_token'] ?? {},
              );
              if (reads++ == 0) {
                entered.complete();
                await release.future;
              }
              return Success(snapshot);
            });
        if (logoutFails) {
          when(
            () => credentials.storeToken(
              key: any(named: 'key'),
              tokenData: any(named: 'tokenData'),
            ),
          ).thenAnswer((_) async => Failure(Exception('disk unavailable')));
        }
        final login = service.signIn();
        await entered.future;
        final logout = service.signOut();
        final logoutExpectation = logoutFails
            ? expectLater(logout, throwsStateError)
            : logout;
        release.complete();
        await logoutExpectation;
        expect((await login).isError(), isTrue);
        expect(browserCalls, 0);
        expect(service.isSignedIn, isFalse);
        expect(renewals, 0);
        if (logoutFails) {
          expect(values['google_oauth_token']!['refreshToken'], 'refresh');
        } else {
          expect((await executor().signInSilently()).isError(), isTrue);
        }
      },
    );
  }

  for (final marker in <Map<String, dynamic>>[
    {'signedOut': true, 'sessionId': 'logout'},
    {'signedOut': 'true', 'sessionId': 'logout'},
    {'signedOut': true},
  ]) {
    test(
      'should never restore tokens alongside logout marker $marker',
      () async {
        final service = executor();
        await service.signInSilently();
        expect(service.isSignedIn, isTrue);
        final residual = {...values['google_oauth_token']!, ...marker};
        if (!marker.containsKey('sessionId')) residual.remove('sessionId');
        values['google_oauth_token'] = residual;
        expect((await service.signInSilently()).isError(), isTrue);
        expect(service.isSignedIn, isFalse);
        expect(service.accessToken, isNull);
        expect((await executor().signInSilently()).isError(), isTrue);
        expect(renewals, 1);
        expect(values['google_oauth_token'], residual);
        await service.signOut();
        expect(
          values['google_oauth_token']!.keys,
          unorderedEquals(['signedOut', 'sessionId']),
        );
        expect((await executor().signInSilently()).isError(), isTrue);
      },
    );
  }

  test('should report unreadable logout confirmation and allow retry after restart', () async {
    final service = executor();
    await service.signInSilently();
    when(
      () => credentials.storeToken(
        key: any(named: 'key'),
        tokenData: any(named: 'tokenData'),
      ),
    ).thenAnswer((call) async {
      values[call.namedArguments[#key] as String] = Map<String, dynamic>.of(
        call.namedArguments[#tokenData] as Map<String, dynamic>,
      );
      return Failure(Exception('write acknowledgement lost'));
    });
    when(() => credentials.getToken(key: 'google_oauth_token'))
        .thenAnswer((_) async => Failure(Exception('read unavailable')));
    await expectLater(service.signOut(), throwsStateError);
    expect(service.isSignedIn, isFalse);
    when(() => credentials.getToken(key: 'google_oauth_token')).thenAnswer(
      (_) async =>
          Success(Map<String, dynamic>.of(values['google_oauth_token']!)),
    );
    final restarted = executor();
    expect((await restarted.signInSilently()).isError(), isTrue);
    await restarted.signOut();
    expect((await executor().signInSilently()).isError(), isTrue);
    expect(renewals, 1);
  });

  for (final change in [
    'logout',
    'replacement',
    'absent',
    'empty-logout',
    'repeated-logout',
    'after-logout',
  ]) {
    test(
      'should not let delayed interactive login overwrite $change',
      () async {
        final authorization = Completer<AccessTokenResponse?>();
        final entered = Completer<void>();
        final transport = MockClient(
          (_) async => http.Response('{"email":"login@example.test"}', 200),
        );
        addTearDown(transport.close);
        if (change == 'absent' || change == 'empty-logout') {
          values.remove('google_oauth_token');
        }
        if (change == 'repeated-logout' || change == 'after-logout') {
          await executor().signOut();
        }
        final ui = GoogleAuthService(
          credentials,
          configurationStore: config,
          httpClient: transport,
          sessionLock: OAuthSessionLock(
            directory: lockDirectory,
            fileName: 'google-session.lock',
          ),
          authorize: () {
            entered.complete();
            return authorization.future;
          },
        );
        await ui.initialize(clientId: 'client', clientSecret: 'secret');
        final login = ui.signIn();
        await entered.future;
        if (change == 'logout' ||
            change == 'empty-logout' ||
            change == 'repeated-logout') {
          await executor().signOut();
          expect(
            values['google_oauth_token']!.keys,
            unorderedEquals(['sessionId', 'signedOut']),
          );
        } else if (change == 'replacement') {
          values['google_oauth_token'] = {
            ...values['google_oauth_token']!,
            'sessionId': 'new-session',
            'accessToken': 'other',
          };
        }
        final before = values['google_oauth_token'] == null
            ? null
            : Map<String, dynamic>.of(values['google_oauth_token']!);
        authorization.complete(
          AccessTokenResponse.fromHttpResponse(
            http.Response(
              jsonEncode({
                'access_token': 'late-login',
                'refresh_token': 'late-refresh',
                'expires_in': 3600,
                'token_type': 'Bearer',
              }),
              200,
            ),
          ),
        );
        final result = await login;
        if (change == 'absent' || change == 'after-logout') {
          expect(result.isSuccess(), isTrue);
          expect(
            (await executor().signInSilently()).getOrThrow().accessToken,
            'late-login',
          );
        } else {
          expect(result.isError(), isTrue);
          expect(values['google_oauth_token'], before);
          if (change == 'logout' ||
              change == 'empty-logout' ||
              change == 'repeated-logout') {
            expect((await executor().signInSilently()).isError(), isTrue);
          }
        }
      },
    );
  }

  for (final committed in [false, true]) {
    test(
      'should reconcile partial shared logout, committed=$committed',
      () async {
        final service = executor();
        await service.signInSilently();
        final before = Map<String, dynamic>.of(values['google_oauth_token']!);
        when(
          () => credentials.storeToken(
            key: any(named: 'key'),
            tokenData: any(named: 'tokenData'),
          ),
        ).thenAnswer((call) async {
          if (committed) {
            values[call.namedArguments[#key]
                as String] = Map<String, dynamic>.of(
              call.namedArguments[#tokenData] as Map<String, dynamic>,
            );
          }
          return Failure(Exception('partial write'));
        });
        if (committed) {
          await service.signOut();
          expect((await executor().signInSilently()).isError(), isTrue);
          expect(
            values['google_oauth_token']!.keys,
            unorderedEquals(['sessionId', 'signedOut']),
          );
        } else {
          await expectLater(service.signOut(), throwsStateError);
          expect(values['google_oauth_token'], before);
          expect(
            (await executor().signInSilently()).getOrThrow().accessToken,
            'fresh',
          );
        }
      },
    );
  }

  for (final change in ['logout', 'new-login', 'competing-refresh']) {
    test(
      'should reject stale renewal after $change in another instance',
      () async {
        final pending = Completer<http.Response>();
        final entered = Completer<void>();
        client.close();
        var requests = 0;
        client = MockClient((request) {
          if (requests++ == 0) {
            entered.complete();
            return pending.future;
          }
          return Future.value(
            http.Response(
              '{"access_token":"winner","refresh_token":"rotated","expires_in":3600,"token_type":"Bearer"}',
              200,
            ),
          );
        });
        final background = executor();
        final renewal = background.signInSilently();
        await entered.future;
        if (change == 'logout') {
          await executor().signOut();
        } else if (change == 'new-login') {
          await OAuthSessionLock(
            directory: lockDirectory,
            fileName: 'google-session.lock',
          ).run(() async {
            values['google_oauth_token'] = {
              'sessionId': 'different-session',
              'clientId': 'client',
              'accessToken': 'winner',
              'refreshToken': 'other-account',
              'email': 'new@example.test',
              'expirationDate': DateTime.now()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
            };
          });
        } else {
          expect(
            (await executor().signInSilently()).getOrThrow().accessToken,
            'winner',
          );
        }
        final persisted = values['google_oauth_token'] == null
            ? null
            : Map<String, dynamic>.of(values['google_oauth_token']!);
        pending.complete(
          http.Response(
            '{"access_token":"stale","expires_in":3600,"token_type":"Bearer"}',
            200,
          ),
        );
        expect((await renewal).isError(), isTrue);
        expect(values['google_oauth_token'], persisted);
        expect(background.isSignedIn, isFalse);
        expect(background.accessToken, isNull);
        if (change == 'logout') {
          expect((await background.signInSilently()).isError(), isTrue);
        } else {
          expect(
            (await background.signInSilently()).getOrThrow().accessToken,
            'winner',
          );
          expect(
            (await executor().signInSilently()).getOrThrow().accessToken,
            'winner',
          );
        }
      },
    );
  }

  for (final scenario in ['missing-expiration', 'empty-token']) {
    test(
      'should refresh changed credentials before concurrent uploads: $scenario',
      () async {
        final service = executor();
        expect((await service.signInSilently()).isSuccess(), isTrue);
        expect(renewals, 1);
        final changed = Map<String, dynamic>.of(values['google_oauth_token']!);
        if (scenario == 'missing-expiration') {
          changed.remove('expirationDate');
          changed['accessToken'] = 'replacement';
        } else {
          changed['accessToken'] = '';
        }
        values['google_oauth_token'] = changed;
        final results = await Future.wait(
          List.generate(3, (_) => service.signInSilently()),
        );
        expect(
          results.every((result) => result.getOrThrow().accessToken == 'fresh'),
          isTrue,
        );
        expect(renewals, 2);
        expect(values['google_oauth_token']!['refreshToken'], 'refresh');
        expect(
          (await executor().signInSilently()).getOrThrow().accessToken,
          'fresh',
        );
        expect(renewals, 2);
      },
    );
  }

  test('should preserve stored credentials after malformed reload and recover after restart', () async {
    final service = executor();
    await service.signInSilently();
    final original = Map<String, dynamic>.of(values['google_oauth_token']!);
    values['google_oauth_token'] = {...original, 'expirationDate': 123};
    expect((await service.signInSilently()).isError(), isTrue);
    expect(values['google_oauth_token']!['refreshToken'], 'refresh');
    expect(renewals, 1);
    values['google_oauth_token'] = original;
    expect((await service.signInSilently()).isSuccess(), isTrue);
    expect((await executor().signInSilently()).isSuccess(), isTrue);
    expect(renewals, 1);
  });

  test(
    'cold service restores config and refreshes without a UI provider',
    () async {
      final service = executor();
      final results = await Future.wait(
        List.generate(3, (_) => service.signInSilently()),
      );
      expect(
        results.every((r) => r.getOrThrow().accessToken == 'fresh'),
        isTrue,
      );
      expect(renewals, 1);
      expect(
        (await executor().signInSilently()).getOrThrow().accessToken,
        'fresh',
      );
      expect(renewals, 1);
    },
  );

  test(
    'missing config can be supplied by UI after service already started',
    () async {
      values.remove(configKey);
      final service = executor();
      expect((await service.signInSilently()).isError(), isTrue);
      await config.write({'clientId': 'client', 'clientSecret': 'secret'});
      expect((await service.signInSilently()).isSuccess(), isTrue);
    },
  );

  test(
    'credentials supplied after cold service startup are reloaded',
    () async {
      final token = values.remove('google_oauth_token')!;
      final service = executor();
      expect((await service.signInSilently()).isError(), isTrue);
      values['google_oauth_token'] = token;
      expect((await service.signInSilently()).isSuccess(), isTrue);
    },
  );

  test(
    'UI migrates legacy config and headless process reads shared copy',
    () async {
      final old = values.remove(configKey)!;
      SharedPreferences.setMockInitialValues({
        configKey: EncryptionService.encrypt(jsonEncode(old)),
      });
      final provider = GoogleAuthProvider(executor());
      addTearDown(provider.dispose);
      await provider.initialize();
      expect(provider.isConfigured, isTrue);
      expect(values[configKey], old);
      SharedPreferences.setMockInitialValues({});
      expect((await executor().signInSilently()).isSuccess(), isTrue);
    },
  );

  test(
    'shared configuration wins over stale Terminal Server preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        configKey: EncryptionService.encrypt(
          jsonEncode({'clientId': 'obsolete'}),
        ),
      });
      expect((await config.readForUi())!['clientId'], 'client');
      await config.remove();
      expect(await config.readForUi(), isNull);
      expect((await executor().signInSilently()).isError(), isTrue);
    },
  );

  test('running service observes logout and removed configuration', () async {
    final service = executor();
    expect((await service.signInSilently()).isSuccess(), isTrue);
    values.remove('google_oauth_token');
    expect((await service.signInSilently()).isError(), isTrue);
    await config.remove();
    expect((await service.signInSilently()).isError(), isTrue);
    expect(renewals, 1);
  });

  test('storage failure is retryable and does not erase credentials', () async {
    final service = executor();
    when(() => credentials.containsKey(key: configKey))
        .thenAnswer((_) async => Failure(Exception('access denied')));
    expect((await service.signInSilently()).isError(), isTrue);
    expect(values['google_oauth_token']!['refreshToken'], 'refresh');
    when(() => credentials.containsKey(key: configKey))
        .thenAnswer((_) async => const Success(true));
    expect((await service.signInSilently()).isSuccess(), isTrue);
  });
}
