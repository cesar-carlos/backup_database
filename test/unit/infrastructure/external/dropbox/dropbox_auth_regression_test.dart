import 'dart:async';
import 'dart:convert';

import 'package:backup_database/application/providers/dropbox_auth_provider.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_client.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_folder_ops.dart';
import 'package:backup_database/infrastructure/external/oauth/oauth_config_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:shared_preferences/shared_preferences.dart';

class _Store extends Mock implements ISecureCredentialService {}

class _Auth extends Mock implements DropboxAuthService {}

class _AuthClient extends Mock implements DropboxAuthClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late Map<String, Map<String, dynamic>> saved;
  late Dio dio;
  late int requests;
  late bool fail;
  Completer<void>? pending;
  late Completer<void> started;
  setUp(() {
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
  DropboxAuthService service() => DropboxAuthService(
    store,
    dio: dio,
    configurationStore: OAuthConfigStore(
      store,
      storageKey: 'dropbox_oauth_config',
      label: 'Dropbox',
    ),
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
    expect(saved.containsKey('dropbox_oauth_token'), isFalse);
    expect(auth.isSignedIn, isFalse);
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
    final auth = _AuthClient();
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
    when(auth.getAuthenticatedDio).thenAnswer((_) async => rd.Success(api));
    when(() => auth.signInSilently(forceRefresh: true)).thenAnswer(
      (_) async => const rd.Success(
        DropboxAuthResult(accessToken: 'fresh', email: 'a@example.com'),
      ),
    );
    expect(
      (await DropboxFolderOps(auth).getOrCreateFolder('/backup')).isError(),
      isTrue,
    );
    expect(calls, 2);
    verify(() => auth.signInSilently(forceRefresh: true)).called(1);
  });
}
