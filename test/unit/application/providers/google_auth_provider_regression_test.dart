import 'dart:async';

import 'package:backup_database/application/providers/google_auth_provider.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart';

class _Service extends Mock implements GoogleAuthService {}

class _Provider extends GoogleAuthProvider {
  _Provider(super.service);
  bool readFails = false;
  bool writeFails = false;
  bool failAfterWrite = false;
  bool failAfterRemove = false;
  Future<void> Function()? beforeWrite;
  Future<void> Function()? beforeRemove;
  String? persistedClient = 'original';
  @override
  Future<Map<String, dynamic>?> loadPersistedConfig() async {
    if (readFails) throw StateError('storage unavailable');
    return persistedClient == null ? null : {'clientId': persistedClient};
  }

  @override
  Future<void> savePersistedConfig(Map<String, dynamic> config) async {
    await beforeWrite?.call();
    if (writeFails) throw StateError('disk unavailable');
    persistedClient = config['clientId'] as String;
    if (failAfterWrite) throw StateError('write acknowledgement failed');
  }

  @override
  Future<void> removePersistedConfig() async {
    await beforeRemove?.call();
    persistedClient = null;
    if (failAfterRemove) throw StateError('remove acknowledgement failed');
  }
}

void main() {
  late _Service service;
  late _Provider provider;
  late bool signedIn;
  late String? email;
  setUp(() {
    service = _Service();
    signedIn = true;
    email = 'original@example.test';
    when(() => service.isSignedIn).thenAnswer((_) => signedIn);
    when(() => service.currentUserEmail).thenAnswer((_) => email);
    when(
      () => service.initialize(
        clientId: any(named: 'clientId'),
        clientSecret: any(named: 'clientSecret'),
      ),
    ).thenAnswer((_) async {});
    when(service.signInSilently).thenAnswer(
      (_) async => const Success(
        GoogleAuthResult(accessToken: 'test', email: 'original@example.test'),
      ),
    );
    provider = _Provider(service);
    when(service.signOut).thenAnswer((_) async {
      signedIn = false;
      email = null;
    });
  });
  tearDown(() => provider.dispose());

  for (final scenario in ['changed', 'same', 'unreadable']) {
    test(
      'should reconcile failed removal with persisted $scenario configuration',
      () async {
        await provider.initialize();
        final entered = Completer<void>();
        final release = Completer<void>();
        provider.beforeRemove = () async {
          entered.complete();
          await release.future;
          if (scenario == 'changed') provider.persistedClient = 'other-process';
          if (scenario == 'unreadable') provider.readFails = true;
          throw StateError('removal failed');
        };
        final removal = provider.removeOAuthConfig();
        await entered.future;
        expect(await provider.signIn(), isFalse);
        release.complete();
        expect(await removal, isFalse);
        expect(provider.isConfigured, scenario == 'same');
        expect(provider.isInitialized, isFalse);
        if (scenario != 'same') {
          expect(await provider.signIn(), isFalse);
          verifyNever(service.signIn);
        }
        provider.readFails = false;
        await provider.initialize();
        expect(provider.isConfigured, isTrue);
        expect(
          provider.oauthConfig!.clientId,
          scenario == 'changed' ? 'other-process' : 'original',
        );
      },
    );
  }

  test('should reconcile configuration committed before write error', () async {
    await provider.initialize();
    provider.failAfterWrite = true;
    expect(await provider.configureOAuth(clientId: 'replacement'), isTrue);
    expect(provider.oauthConfig!.clientId, 'replacement');
    expect(provider.isConfigured, isTrue);
  });

  test('should reconcile removal committed before error', () async {
    await provider.initialize();
    provider.failAfterRemove = true;
    expect(await provider.removeOAuthConfig(), isTrue);
    expect(provider.oauthConfig, isNull);
    expect(provider.isConfigured, isFalse);
    await provider.initialize();
    expect(provider.oauthConfig, isNull);
    expect(provider.isConfigured, isFalse);
  });

  test('should retry initialization of persisted replacement', () async {
    await provider.initialize();
    when(() => service.initialize(clientId: 'replacement'))
        .thenThrow(StateError('temporary failure'));
    expect(await provider.configureOAuth(clientId: 'replacement'), isFalse);
    expect(provider.isInitialized, isFalse);
    when(() => service.initialize(clientId: 'replacement'))
        .thenAnswer((_) async {});
    await provider.initialize();
    expect(provider.isInitialized, isTrue);
    expect(provider.isConfigured, isTrue);
    expect(provider.oauthConfig!.clientId, 'replacement');
  });

  test('should block login if failed write cannot be reconciled', () async {
    await provider.initialize();
    provider.failAfterWrite = true;
    provider.readFails = true;
    expect(await provider.configureOAuth(clientId: 'replacement'), isFalse);
    expect(provider.isConfigured, isFalse);
    expect(await provider.signIn(), isFalse);
    provider.readFails = false;
    await provider.initialize();
    expect(provider.oauthConfig!.clientId, 'replacement');
    expect(provider.isConfigured, isTrue);
  });

  test('should serialize pending save before configuration removal', () async {
    await provider.initialize();
    final entered = Completer<void>();
    final release = Completer<void>();
    provider.beforeWrite = () {
      entered.complete();
      return release.future;
    };
    final saving = provider.configureOAuth(clientId: 'replacement');
    await entered.future;
    final removing = provider.removeOAuthConfig();
    expect(await provider.signIn(), isFalse);
    release.complete();
    expect(await saving, isTrue);
    expect(await removing, isTrue);
    expect(provider.persistedClient, isNull);
    expect(provider.oauthConfig, isNull);
    expect(provider.isConfigured, isFalse);
  });

  test('should continue queued configuration after failed save', () async {
    await provider.initialize();
    final entered = Completer<void>();
    final release = Completer<void>();
    var writes = 0;
    provider.beforeWrite = () async {
      if (writes++ == 0) {
        entered.complete();
        await release.future;
        throw StateError('first write failed');
      }
    };
    final first = provider.configureOAuth(clientId: 'first');
    await entered.future;
    final second = provider.configureOAuth(clientId: 'second');
    release.complete();
    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(provider.persistedClient, 'second');
    expect(provider.oauthConfig!.clientId, 'second');
  });

  for (final throwsError in [false, true]) {
    test(
      'should preserve logout error after late login, throws=$throwsError',
      () async {
        await provider.initialize();
        final loginResult = Completer<Result<GoogleAuthResult>>();
        when(service.signIn).thenAnswer((_) => loginResult.future);
        final login = provider.signIn();
        expect(await provider.signIn(), isFalse);
        when(service.signOut)
            .thenThrow(StateError('logout persistence failed'));
        await provider.signOut();
        final logoutError = provider.error;
        if (throwsError) {
          loginResult.completeError(StateError('old login failed'));
        } else {
          loginResult.complete(
            const Success(
              GoogleAuthResult(accessToken: 'late', email: 'late@example.test'),
            ),
          );
        }
        expect(await login, isFalse);
        expect(provider.error, logoutError);
        expect(provider.currentEmail, 'original@example.test');
      },
    );
  }

  test(
    'should block login if persisted configuration cannot initialize',
    () async {
      await provider.initialize();
      when(() => service.initialize(clientId: 'replacement'))
          .thenThrow(StateError('initialization failed'));
      expect(await provider.configureOAuth(clientId: 'replacement'), isFalse);
      expect(provider.persistedClient, 'replacement');
      expect(provider.isConfigured, isFalse);
      expect(await provider.signIn(), isFalse);
      verifyNever(service.signIn);
    },
  );

  test('should hide stale email when logout persistence fails', () async {
    await provider.initialize();
    when(service.signOut).thenAnswer((_) async {
      signedIn = false;
      email = null;
      throw StateError('logout write failed');
    });
    await provider.signOut();
    expect(provider.currentEmail, isNull);
    expect(provider.isSignedIn, isFalse);
    expect(provider.error, isNotNull);
  });

  test('should display service account after credentials change', () async {
    await provider.initialize();
    email = 'replacement@example.test';
    expect(provider.currentEmail, email);
  });

  test('should retry initialization after configuration read fails', () async {
    provider.readFails = true;
    await provider.initialize();
    expect(provider.isInitialized, isFalse);
    provider.readFails = false;
    await provider.initialize();
    expect(provider.isInitialized, isTrue);
    expect(provider.isConfigured, isTrue);
    expect(provider.currentEmail, email);
  });

  test(
    'should preserve configuration when replacement cannot be saved',
    () async {
      await provider.initialize();
      provider.writeFails = true;
      expect(await provider.configureOAuth(clientId: 'replacement'), isFalse);
      expect(provider.oauthConfig!.clientId, 'original');
      expect(provider.isConfigured, isTrue);
      verifyNever(() => service.initialize(clientId: 'replacement'));
    },
  );
}
