import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/providers/dropbox_auth_provider.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_client.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_folder_ops.dart';
import 'package:backup_database/infrastructure/external/oauth/oauth_config_store.dart';
import 'package:backup_database/infrastructure/external/oauth/oauth_session_lock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:shared_preferences/shared_preferences.dart';

class _Store extends Mock implements ISecureCredentialService {}

class _Auth extends Mock implements DropboxAuthService {}

class _FolderAuthClient extends DropboxAuthClient {
  _FolderAuthClient(super.authService, this.api);
  final Dio api;
  @override
  Future<rd.Result<Dio>> getAuthenticatedDio() async => rd.Success(api);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late Map<String, Map<String, dynamic>> saved;
  late Dio dio;
  late int requests;
  late bool fail;
  Completer<void>? pending;
  late Completer<void> started;
  late Directory lockDirectory;
  setUp(() async {
    lockDirectory = await Directory.systemTemp.createTemp(
      'dropbox-session-test-',
    );
    addTearDown(() => lockDirectory.delete(recursive: true));
    SharedPreferences.setMockInitialValues({});
    EncryptionService.initializeWithDeviceKey('dropbox-regression');
    addTearDown(EncryptionService.resetToLegacy);
    store = _Store();
    saved = {
      'dropbox_oauth_config': {'clientId': 'client'},
      'dropbox_oauth_token': {
        'accessToken': 'old',
        'refreshToken': 'refresh',
        'email': 'a@example.com',
        'expirationDate': '2020-01-01T00:00:00Z',
      },
    };
    when(() => store.containsKey(key: any(named: 'key'))).thenAnswer(
      (c) async => rd.Success(saved.containsKey(c.namedArguments[#key])),
    );
    when(() => store.getToken(key: any(named: 'key'))).thenAnswer(
      (c) async => rd.Success(
        Map<String, dynamic>.of(saved[c.namedArguments[#key]] ?? {}),
      ),
    );
    when(
      () => store.storeToken(
        key: any(named: 'key'),
        tokenData: any(named: 'tokenData'),
      ),
    ).thenAnswer((c) async {
      saved[c.namedArguments[#key] as String] = Map<String, dynamic>.of(
        c.namedArguments[#tokenData] as Map<String, dynamic>,
      );
      return const rd.Success(unit);
    });
    when(() => store.deleteToken(key: any(named: 'key'))).thenAnswer((c) async {
      saved.remove(c.namedArguments[#key]);
      return const rd.Success(unit);
    });
    requests = 0;
    fail = false;
    pending = null;
    started = Completer<void>();
    dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests++;
          if (!started.isCompleted) started.complete();
          await pending?.future;
          if (fail) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
              ),
            );
          } else {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'access_token': 'fresh', 'expires_in': 3600},
              ),
            );
          }
        },
      ),
    );
    addTearDown(() => dio.close(force: true));
  });
  DropboxAuthService service({
    Duration requestTimeout = const Duration(seconds: 30),
    Duration acquisitionTimeout = const Duration(seconds: 10),
    Future<Map<String, dynamic>?> Function()? authorize,
  }) => DropboxAuthService(
    store,
    dio: dio,
    requestTimeout: requestTimeout,
    authorize: authorize,
    sessionLock: OAuthSessionLock(
      directory: lockDirectory,
      acquisitionTimeout: acquisitionTimeout,
    ),
    configurationStore: OAuthConfigStore(
      store,
      storageKey: 'dropbox_oauth_config',
      label: 'Dropbox',
      sessionLock: OAuthSessionLock(
        directory: lockDirectory,
        fileName: 'dropbox-config.lock',
      ),
    ),
  );

  test('should time out logout behind a pending write and recover on explicit retry', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var writes = 0;
    when(
      () => store.storeToken(
        key: 'dropbox_oauth_token',
        tokenData: any(named: 'tokenData'),
      ),
    ).thenAnswer((call) async {
      if (writes++ == 0) {
        entered.complete();
        await release.future;
      }
      saved['dropbox_oauth_token'] = Map<String, dynamic>.of(
        call.namedArguments[#tokenData] as Map<String, dynamic>,
      );
      return const rd.Success(unit);
    });
    final auth = service(acquisitionTimeout: const Duration(milliseconds: 100));
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
    expect(saved['dropbox_oauth_token']!['signedOut'], isNull);
    await service().signOut();
    expect((await service().signInSilently()).isError(), isTrue);
    expect(saved['dropbox_oauth_token']!['signedOut'], isTrue);
  });

  for (final change in [
    'logout',
    'empty-logout',
    'new-login',
    'partial-logout',
  ]) {
    test(
      'should reject browser login after $change in another instance',
      () async {
        if (change == 'empty-logout') saved.remove('dropbox_oauth_token');
        final entered = Completer<void>();
        final response = Completer<Map<String, dynamic>?>();
        final auth = service(
          authorize: () {
            entered.complete();
            return response.future;
          },
        );
        dio.interceptors.clear();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'email': 'login@example.com'},
                ),
              );
            },
          ),
        );
        await auth.initialize(clientId: 'client');
        final login = auth.signIn();
        await entered.future;
        if (change == 'new-login') {
          final other = service(
            authorize: () async => {
              'access_token': 'winner',
              'refresh_token': 'winner-refresh',
              'expires_in': 3600,
            },
          );
          await other.initialize(clientId: 'client');
          expect((await other.signIn()).isSuccess(), isTrue);
        } else {
          if (change == 'partial-logout') {
            when(
              () => store.storeToken(
                key: 'dropbox_oauth_token',
                tokenData: any(named: 'tokenData'),
              ),
            ).thenAnswer((call) async {
              saved['dropbox_oauth_token'] = Map<String, dynamic>.of(
                call.namedArguments[#tokenData] as Map<String, dynamic>,
              );
              return rd.Failure(Exception('write acknowledgement lost'));
            });
          }
          await service().signOut();
        }
        final persisted = Map<String, dynamic>.of(
          saved['dropbox_oauth_token']!,
        );
        response.complete({
          'access_token': 'stale',
          'refresh_token': 'stale-refresh',
          'expires_in': 3600,
        });
        expect((await login).isError(), isTrue);
        expect(saved['dropbox_oauth_token'], persisted);
        expect(auth.accessToken, isNull);
        final restored = await service().signInSilently();
        expect(restored.isSuccess(), change == 'new-login');
      },
    );
  }

  test(
    'should not publish browser credentials when persistence fails',
    () async {
      saved.remove('dropbox_oauth_token');
      final auth = service(
        authorize: () async => {
          'access_token': 'uncommitted',
          'refresh_token': 'refresh',
          'expires_in': 3600,
        },
      );
      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'email': 'login@example.com'},
              ),
            );
          },
        ),
      );
      when(
        () => store.storeToken(
          key: 'dropbox_oauth_token',
          tokenData: any(named: 'tokenData'),
        ),
      ).thenAnswer((_) async => rd.Failure(Exception('disk unavailable')));
      await auth.initialize(clientId: 'client');
      expect((await auth.signIn()).isError(), isTrue);
      expect(auth.isSignedIn, isFalse);
      expect(auth.accessToken, isNull);
      expect((await service().signInSilently()).isError(), isTrue);
    },
  );

  test(
    'should ignore a refresh completed after timeout and recover after restart',
    () async {
      pending = Completer<void>();
      final release = pending!;
      final auth = service(requestTimeout: const Duration(milliseconds: 50));
      final work = auth.signInSilently();
      await started.future;
      expect((await work).isError(), isTrue);
      expect(saved['dropbox_oauth_token']!['accessToken'], 'old');
      await auth.signOut();
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(saved['dropbox_oauth_token']!['signedOut'], isTrue);
      expect(
        saved['dropbox_oauth_token']!.keys,
        unorderedEquals(['signedOut', 'sessionId']),
      );
      expect(auth.isSignedIn, isFalse);
      pending = null;
      expect((await service().signInSilently()).isError(), isTrue);
      expect(requests, 1);
    },
  );

  for (final committed in [true, false]) {
    test(
      'should verify ambiguous Dropbox credential write, committed=$committed',
      () async {
        when(
          () => store.storeToken(
            key: 'dropbox_oauth_token',
            tokenData: any(named: 'tokenData'),
          ),
        ).thenAnswer((call) async {
          if (committed) {
            saved['dropbox_oauth_token'] = Map<String, dynamic>.of(
              call.namedArguments[#tokenData] as Map<String, dynamic>,
            );
          }
          return rd.Failure(Exception('storage response failed'));
        });
        final auth = service();
        final result = await auth.signInSilently();
        expect(result.isSuccess(), committed);
        expect(auth.accessToken, committed ? 'fresh' : 'old');
        expect(saved['dropbox_oauth_token']!['refreshToken'], 'refresh');
        when(
          () => store.storeToken(
            key: 'dropbox_oauth_token',
            tokenData: any(named: 'tokenData'),
          ),
        ).thenAnswer((call) async {
          saved['dropbox_oauth_token'] = Map<String, dynamic>.of(
            call.namedArguments[#tokenData] as Map<String, dynamic>,
          );
          return const rd.Success(unit);
        });
        expect((await service().signInSilently()).isSuccess(), isTrue);
        expect(requests, committed ? 1 : 2);
      },
    );
  }

  test(
    'should not partially update cached credentials after malformed reload',
    () async {
      final auth = service();
      expect((await auth.signInSilently()).isSuccess(), isTrue);
      saved['dropbox_oauth_token']!['accessToken'] = 'partial';
      saved['dropbox_oauth_token']!['refreshToken'] = 123;
      expect((await auth.signInSilently()).isError(), isTrue);
      expect(auth.accessToken, 'fresh');
      expect(requests, 1);
      saved['dropbox_oauth_token']!['refreshToken'] = 'refresh';
      expect(
        (await service().signInSilently()).getOrThrow().accessToken,
        'partial',
      );
    },
  );

  test(
    'headless refresh coalesces and preserves refresh token across restart',
    () async {
      final auth = service();
      final results = await Future.wait(
        List.generate(3, (_) => auth.signInSilently()),
      );
      expect(results.every((r) => r.isSuccess()), isTrue);
      expect(requests, 1);
      expect(saved['dropbox_oauth_token']!['refreshToken'], 'refresh');
      expect((await service().signInSilently()).isSuccess(), isTrue);
      expect(requests, 1);
    },
  );
  test('legacy UI configuration migrates for the headless executor', () async {
    final config = saved.remove('dropbox_oauth_config')!;
    SharedPreferences.setMockInitialValues({
      'dropbox_oauth_config': EncryptionService.encrypt(jsonEncode(config)),
    });
    final provider = DropboxAuthProvider(service());
    addTearDown(provider.dispose);
    await provider.initialize();
    expect(provider.isConfigured, isTrue);
    expect(saved['dropbox_oauth_config'], config);
    SharedPreferences.setMockInitialValues({});
    expect((await service().signInSilently()).isSuccess(), isTrue);
  });

  test('running executor observes a removed token', () async {
    final auth = service();
    expect((await auth.signInSilently()).isSuccess(), isTrue);
    saved.remove('dropbox_oauth_token');
    expect((await auth.signInSilently()).isError(), isTrue);
    expect(auth.isSignedIn, isFalse);
  });

  test('unknown expiration triggers renewal', () async {
    saved['dropbox_oauth_token']!.remove('expirationDate');
    expect((await service().signInSilently()).isSuccess(), isTrue);
    expect(requests, 1);
  });

  for (final responseLost in [false, true]) {
    test(
      'should retain logout lock after caller timeout until marker settles, responseLost=$responseLost',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        var browserOpened = false;
        when(
          () => store.storeToken(
            key: 'dropbox_oauth_token',
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
          saved['dropbox_oauth_token'] = data;
          if (responseLost && data['signedOut'] == true) {
            return rd.Failure(Exception('write acknowledgement lost'));
          }
          return const rd.Success(unit);
        });
        dio.interceptors.clear();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'email': 'new@example.com'},
                ),
              );
            },
          ),
        );
        final ui = service(
          authorize: () async {
            browserOpened = true;
            return {
              'access_token': 'new-login',
              'refresh_token': 'new-refresh',
              'expires_in': 3600,
            };
          },
        );
        await ui.initialize(clientId: 'client');
        final logout = service().signOut();
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
        expect(saved['dropbox_oauth_token']!['accessToken'], 'new-login');
        expect(
          (await service().signInSilently()).getOrThrow().accessToken,
          'new-login',
        );
      },
    );
  }

  for (final writeFailure in [false, true]) {
    test(
      'should isolate delayed renewal from a new login, writeFailure=$writeFailure',
      () async {
        final oldResponse = Completer<void>();
        final newResponse = Completer<void>();
        final oldEntered = Completer<void>();
        final newEntered = Completer<void>();
        var renewals = 0;
        dio.interceptors.clear();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              if (options.path != '/oauth2/token') {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'email': 'new@example.com'},
                  ),
                );
                return;
              }
              final index = ++renewals;
              if (index == 1) {
                oldEntered.complete();
                await oldResponse.future;
              } else {
                if (!newEntered.isCompleted) newEntered.complete();
                await newResponse.future;
              }
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'access_token': 'renewal-$index', 'expires_in': 3600},
                ),
              );
            },
          ),
        );
        if (writeFailure) {
          when(
            () => store.storeToken(
              key: 'dropbox_oauth_token',
              tokenData: any(named: 'tokenData'),
            ),
          ).thenAnswer((call) async {
            saved['dropbox_oauth_token'] = Map<String, dynamic>.of(
              call.namedArguments[#tokenData] as Map<String, dynamic>,
            );
            return rd.Failure(Exception('write response lost'));
          });
        }
        final auth = service(
          authorize: () async => {
            'access_token': 'login',
            'refresh_token': 'login-refresh',
            'expires_in': 3600,
          },
        );
        final oldWork = auth.signInSilently();
        await oldEntered.future;
        expect((await auth.signIn()).isSuccess(), isTrue);
        final current = auth.signInSilently(forceRefresh: true);
        try {
          await newEntered.future.timeout(const Duration(seconds: 2));
          oldResponse.complete();
          expect((await oldWork).isError(), isTrue);
          final joined = auth.signInSilently(forceRefresh: true);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(renewals, 2);
          newResponse.complete();
          expect((await current).getOrThrow().accessToken, 'renewal-2');
          expect((await joined).getOrThrow().accessToken, 'renewal-2');
          expect(
            (await service().signInSilently()).getOrThrow().refreshToken,
            'login-refresh',
          );
        } finally {
          if (!oldResponse.isCompleted) oldResponse.complete();
          if (!newResponse.isCompleted) newResponse.complete();
          await oldWork;
          await current;
        }
      },
    );
  }

  for (final committed in [true, false]) {
    test(
      'should publish renewal only after write confirmation, committed=$committed',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        when(
          () => store.storeToken(
            key: 'dropbox_oauth_token',
            tokenData: any(named: 'tokenData'),
          ),
        ).thenAnswer((call) async {
          entered.complete();
          await release.future;
          if (committed) {
            saved['dropbox_oauth_token'] = Map<String, dynamic>.of(
              call.namedArguments[#tokenData] as Map<String, dynamic>,
            );
          }
          return rd.Failure(Exception('write response failed'));
        });
        final auth = service();
        final renewal = auth.signInSilently();
        await entered.future;
        expect(auth.accessToken, 'old');
        release.complete();
        expect((await renewal).isSuccess(), committed);
        expect(auth.accessToken, committed ? 'fresh' : 'old');
      },
    );
  }

  test(
    'should preserve refresh token when renewal returns an empty replacement',
    () async {
      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'access_token': 'fresh',
                  'refresh_token': '',
                  'expires_in': 3600,
                },
              ),
            );
          },
        ),
      );
      expect((await service().signInSilently()).isSuccess(), isTrue);
      expect(saved['dropbox_oauth_token']!['refreshToken'], 'refresh');
      expect(
        (await service().signInSilently()).getOrThrow().refreshToken,
        'refresh',
      );
      expect(requests, 1);
    },
  );

  test('should allow login after a concurrent renewal commits with an error response', () async {
    saved['dropbox_oauth_token']!['sessionId'] = 'existing-session';
    saved['dropbox_oauth_token']!['clientId'] = 'client';
    final entered = Completer<void>();
    final response = Completer<Map<String, dynamic>?>();
    final auth = service(
      authorize: () {
        entered.complete();
        return response.future;
      },
    );
    dio.interceptors.clear();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: options.path == '/oauth2/token'
                  ? {
                      'access_token': 'renewed',
                      'refresh_token': 'rotated',
                      'expires_in': 3600,
                    }
                  : {'email': 'new@example.com'},
            ),
          );
        },
      ),
    );
    when(
      () => store.storeToken(
        key: 'dropbox_oauth_token',
        tokenData: any(named: 'tokenData'),
      ),
    ).thenAnswer((call) async {
      saved['dropbox_oauth_token'] = Map<String, dynamic>.of(
        call.namedArguments[#tokenData] as Map<String, dynamic>,
      );
      return rd.Failure(Exception('write acknowledgement lost'));
    });
    await auth.initialize(clientId: 'client');
    final login = auth.signIn();
    await entered.future;
    expect((await service().signInSilently()).isSuccess(), isTrue);
    response.complete({
      'access_token': 'login',
      'refresh_token': 'login-refresh',
      'expires_in': 3600,
    });
    expect((await login).isSuccess(), isTrue);
    expect(
      saved['dropbox_oauth_token']!['sessionId'],
      isNot('existing-session'),
    );
    expect(
      (await service().signInSilently()).getOrThrow().accessToken,
      'login',
    );
  });

  for (final marker in <Map<String, dynamic>>[
    {'signedOut': true, 'sessionId': 'logout'},
    {'signedOut': 'true', 'sessionId': 'logout'},
    {'signedOut': true},
  ]) {
    test(
      'should reject residual tokens with logout marker $marker after restart',
      () async {
        final auth = service();
        await auth.signInSilently();
        final residual = {...saved['dropbox_oauth_token']!, ...marker};
        if (!marker.containsKey('sessionId')) residual.remove('sessionId');
        saved['dropbox_oauth_token'] = residual;
        expect((await auth.signInSilently()).isError(), isTrue);
        expect(auth.accessToken, isNull);
        expect((await service().signInSilently()).isError(), isTrue);
        expect(requests, 1);
        await service().signOut();
        expect(
          saved['dropbox_oauth_token']!.keys,
          unorderedEquals(['signedOut', 'sessionId']),
        );
      },
    );
  }

  test('should preserve committed logout when confirmation is unreadable and restart', () async {
    when(
      () => store.storeToken(
        key: 'dropbox_oauth_token',
        tokenData: any(named: 'tokenData'),
      ),
    ).thenAnswer((call) async {
      saved['dropbox_oauth_token'] = Map<String, dynamic>.of(
        call.namedArguments[#tokenData] as Map<String, dynamic>,
      );
      return rd.Failure(Exception('write response lost'));
    });
    when(() => store.getToken(key: 'dropbox_oauth_token'))
        .thenAnswer((_) async => rd.Failure(Exception('read unavailable')));
    await expectLater(service().signOut(), throwsStateError);
    when(() => store.getToken(key: 'dropbox_oauth_token')).thenAnswer(
      (_) async =>
          rd.Success(Map<String, dynamic>.of(saved['dropbox_oauth_token']!)),
    );
    expect((await service().signInSilently()).isError(), isTrue);
    await service().signOut();
    expect((await service().signInSilently()).isError(), isTrue);
    expect(requests, 0);
  });

  for (final committed in [true, false]) {
    test(
      'should reconcile partial logout during renewal, committed=$committed',
      () async {
        pending = Completer<void>();
        final background = service();
        final renewal = background.signInSilently();
        await started.future;
        when(
          () => store.storeToken(
            key: 'dropbox_oauth_token',
            tokenData: any(named: 'tokenData'),
          ),
        ).thenAnswer((call) async {
          final data = Map<String, dynamic>.of(
            call.namedArguments[#tokenData] as Map<String, dynamic>,
          );
          if (committed || data['signedOut'] != true) {
            saved['dropbox_oauth_token'] = data;
          }
          if (data['signedOut'] == true) {
            return rd.Failure(Exception('write response failed'));
          }
          return const rd.Success(unit);
        });
        final logout = service().signOut();
        if (committed) {
          await logout;
        } else {
          await expectLater(logout, throwsStateError);
        }
        pending!.complete();
        expect((await renewal).isSuccess(), !committed);
        expect((await service().signInSilently()).isSuccess(), !committed);
        if (committed) {
          expect(background.accessToken, isNull);
          expect(saved['dropbox_oauth_token']!['signedOut'], isTrue);
          expect(
            saved['dropbox_oauth_token']!.keys,
            unorderedEquals(['signedOut', 'sessionId']),
          );
        }
      },
    );
  }

  test(
    'should keep logout serialized behind an ambiguous renewal write',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      when(
        () => store.storeToken(
          key: 'dropbox_oauth_token',
          tokenData: any(named: 'tokenData'),
        ),
      ).thenAnswer((call) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        saved['dropbox_oauth_token'] = Map<String, dynamic>.of(
          call.namedArguments[#tokenData] as Map<String, dynamic>,
        );
        return rd.Failure(Exception('write response failed'));
      });
      final renewal = service().signInSilently();
      await entered.future;
      final logout = service().signOut();
      release.complete();
      await renewal;
      await logout;
      expect(saved['dropbox_oauth_token']!['signedOut'], isTrue);
      expect(
        saved['dropbox_oauth_token']!.keys,
        unorderedEquals(['signedOut', 'sessionId']),
      );
      expect((await service().signInSilently()).isError(), isTrue);
    },
  );

  test('network failure preserves credentials and allows retry', () async {
    fail = true;
    final auth = service();
    expect((await auth.signInSilently()).isError(), isTrue);
    expect(saved['dropbox_oauth_token']!['refreshToken'], 'refresh');
    fail = false;
    expect((await auth.signInSilently()).isSuccess(), isTrue);
  });
  test('late refresh cannot restore credentials after logout', () async {
    pending = Completer<void>();
    final auth = service();
    final work = auth.signInSilently();
    await started.future;
    await auth.signOut();
    pending!.complete();
    expect((await work).isError(), isTrue);
    expect(saved['dropbox_oauth_token']!['signedOut'], isTrue);
    expect(
      saved['dropbox_oauth_token']!.keys,
      unorderedEquals(['signedOut', 'sessionId']),
    );
    expect(auth.isSignedIn, isFalse);
  });
  test(
    'logout in another service object rejects the in-flight refresh',
    () async {
      pending = Completer<void>();
      final background = service();
      final work = background.signInSilently();
      await started.future;
      await service().signOut();
      pending!.complete();
      expect((await work).isError(), isTrue);
      expect(saved['dropbox_oauth_token']!['signedOut'], isTrue);
      expect(
        saved['dropbox_oauth_token']!.keys,
        unorderedEquals(['signedOut', 'sessionId']),
      );
      expect(background.isSignedIn, isFalse);
      expect(background.accessToken, isNull);
    },
  );

  test(
    'another session replacement cannot be overwritten by stale refresh',
    () async {
      pending = Completer<void>();
      final background = service();
      final work = background.signInSilently();
      await started.future;
      await OAuthSessionLock(directory: lockDirectory).run(() async {
        saved['dropbox_oauth_token'] = {
          'sessionId': 'replacement',
          'accessToken': 'replacement',
          'refreshToken': 'other-refresh',
          'email': 'other@example.com',
        };
      });
      pending!.complete();
      expect((await work).isError(), isTrue);
      expect(saved['dropbox_oauth_token']!['accessToken'], 'replacement');
      expect(background.isSignedIn, isFalse);
      expect(background.accessToken, isNull);
    },
  );

  test(
    'concurrent forced refresh is not lost behind a normal restore',
    () async {
      saved['dropbox_oauth_token']!['expirationDate'] = DateTime.now()
          .add(const Duration(hours: 2))
          .toIso8601String();
      final auth = service();
      final normal = auth.signInSilently();
      final forced = auth.signInSilently(forceRefresh: true);
      final secondForced = auth.signInSilently(forceRefresh: true);
      expect((await normal).getOrThrow().accessToken, 'old');
      expect((await forced).getOrThrow().accessToken, 'fresh');
      expect((await secondForced).getOrThrow().accessToken, 'fresh');
      expect(requests, 1);
    },
  );

  test('forced caller reuses a normal restore that already renewed', () async {
    final auth = service();
    final normal = auth.signInSilently();
    final forced = auth.signInSilently(forceRefresh: true);
    expect((await normal).isSuccess(), isTrue);
    expect((await forced).isSuccess(), isTrue);
    expect(requests, 1);
  });

  test('force refresh renews even before expiration', () async {
    saved['dropbox_oauth_token']!['expirationDate'] = DateTime.now()
        .add(const Duration(hours: 2))
        .toIso8601String();
    final auth = service();
    expect((await auth.signInSilently()).isSuccess(), isTrue);
    expect(requests, 0);
    expect((await auth.signInSilently(forceRefresh: true)).isSuccess(), isTrue);
    expect(requests, 1);
  });
  test(
    'upload authentication never opens interactive login on failure',
    () async {
      final auth = _Auth();
      when(auth.signInSilently).thenAnswer(
        (_) async => const rd.Failure(DropboxFailure(message: 'network')),
      );
      expect(
        (await DropboxAuthClient(auth).getAuthenticatedDio()).isError(),
        isTrue,
      );
      verifyNever(auth.signIn);
    },
  );
  test('persistent folder 401 refreshes only once', () async {
    final auth = _Auth();
    final api = Dio();
    addTearDown(() => api.close(force: true));
    var calls = 0;
    api.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          calls++;
          h.reject(
            DioException(
              requestOptions: o,
              response: Response(requestOptions: o, statusCode: 401),
            ),
          );
        },
      ),
    );
    when(() => auth.signInSilently(forceRefresh: true)).thenAnswer(
      (_) async => const rd.Success(
        DropboxAuthResult(accessToken: 'fresh', email: 'a@example.com'),
      ),
    );
    expect(
      (await DropboxFolderOps(_FolderAuthClient(auth, api))
              .getOrCreateFolder('/backup'))
          .isError(),
      isTrue,
    );
    expect(calls, 2);
    verify(() => auth.signInSilently(forceRefresh: true)).called(1);
  });
}
