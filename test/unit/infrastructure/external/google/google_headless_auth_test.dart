import 'dart:convert';

import 'package:backup_database/application/providers/google_auth_provider.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';
import 'package:backup_database/infrastructure/external/google/google_oauth_config_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
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
  const configKey = GoogleOAuthConfigStore.key;
  setUp(() {
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
  tearDown(() {
    client.close();
    EncryptionService.resetToLegacy();
  });

  GoogleAuthService executor() => GoogleAuthService(
    credentials,
    configurationStore: config,
    httpClient: client,
    authorize: () => throw StateError('Headless must not open a browser'),
  );

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
