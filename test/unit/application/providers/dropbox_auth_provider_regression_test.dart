import 'dart:async';

import 'package:backup_database/application/providers/dropbox_auth_provider.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart';

class _Service extends Mock implements DropboxAuthService {}

class _Provider extends DropboxAuthProvider {
  _Provider(super.service);
  final writing = Completer<void>();
  final release = Completer<void>();
  String? saved;
  bool failAfterRemove = false;
  bool replaceDuringRemove = false;
  @override
  Future<Map<String, dynamic>?> loadPersistedConfig() async =>
      failAfterRemove && saved == null
      ? null
      : {'clientId': saved ?? 'original'};
  @override
  Future<void> savePersistedConfig(Map<String, dynamic> config) async {
    writing.complete();
    await release.future;
    saved = config['clientId'] as String;
  }

  @override
  Future<void> removePersistedConfig() async {
    if (replaceDuringRemove) {
      saved = 'other-process';
      throw StateError('removal failed');
    }
    saved = null;
    if (failAfterRemove) throw StateError('remove acknowledgement failed');
  }
}

void main() {
  test('should block Dropbox login after failed removal detects a different configuration', () async {
    final service = _Service();
    when(
      () => service.initialize(
        clientId: any(named: 'clientId'),
        clientSecret: any(named: 'clientSecret'),
      ),
    ).thenAnswer((_) async {});
    when(service.signInSilently).thenAnswer(
      (_) async => const Success(
        DropboxAuthResult(accessToken: 'token', email: 'user@example.test'),
      ),
    );
    when(service.signOut).thenAnswer((_) async {});
    final provider = _Provider(service)..replaceDuringRemove = true;
    addTearDown(provider.dispose);
    await provider.initialize();
    expect(await provider.removeOAuthConfig(), isFalse);
    expect(provider.isConfigured, isFalse);
    expect(await provider.signIn(), isFalse);
    verifyNever(service.signIn);
    await provider.initialize();
    expect(provider.oauthConfig!.clientId, 'other-process');
    expect(provider.isConfigured, isTrue);
  });

  test('should serialize Dropbox removal after save and reject login during changes', () async {
    final service = _Service();
    when(
      () => service.initialize(
        clientId: any(named: 'clientId'),
        clientSecret: any(named: 'clientSecret'),
      ),
    ).thenAnswer((_) async {});
    when(service.signInSilently).thenAnswer(
      (_) async => const Success(
        DropboxAuthResult(accessToken: 'token', email: 'user@example.test'),
      ),
    );
    when(service.signOut).thenAnswer((_) async {});
    final provider = _Provider(service);
    addTearDown(provider.dispose);
    await provider.initialize();
    final save = provider.configureOAuth(clientId: 'replacement');
    await provider.writing.future;
    provider.failAfterRemove = true;
    final remove = provider.removeOAuthConfig();
    expect(await provider.signIn(), isFalse);
    provider.release.complete();
    expect(await save, isTrue);
    expect(await remove, isTrue);
    expect(provider.saved, isNull);
    expect(provider.isConfigured, isFalse);
    verifyNever(service.signIn);
  });
}
