import 'dart:async';

import 'package:backup_database/application/providers/oauth_provider_base.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/utils/window_close_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Provider extends OAuthProviderBase<String, String> {
  _Provider(Future<Result<String>> Function() signIn)
    : super(
        oauthConfigPrefsKey: 'test_oauth',
        serviceLabel: 'test',
        initializeService: ({required clientId, clientSecret}) async {},
        signInService: signIn,
        signInSilentlyService: () async => const Success('user'),
        signOutService: () async {},
      );
  @override
  bool get isSignedIn => false;
  @override
  String? get currentUserEmailFromService => null;
  @override
  String? get accessTokenFromService => null;
  @override
  String buildConfig({required String clientId, String? clientSecret}) =>
      clientId;
  @override
  Map<String, dynamic> configToJson(String config) => {'id': config};
  @override
  String configFromJson(Map<String, dynamic> json) => json['id'] as String;
  @override
  String emailOf(String result) => result;
  @override
  String clientIdOf(String config) => config;
  @override
  String? clientSecretOf(String config) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EncryptionService.initializeWithDeviceKey('test-window-close');
  });
  tearDown(EncryptionService.resetToLegacy);

  test(
    'OAuth releases only its own close guard on success and failure',
    () async {
      final firstResult = Completer<Result<String>>();
      final secondResult = Completer<Result<String>>();
      final first = _Provider(() => firstResult.future);
      final second = _Provider(() => secondResult.future);
      expect(await first.configureOAuth(clientId: 'one'), isTrue);
      expect(await second.configureOAuth(clientId: 'two'), isTrue);
      final firstLogin = first.signIn();
      final secondLogin = second.signIn();
      expect(WindowCloseGuard.isBlocked, isTrue);
      firstResult.complete(const Success('user'));
      expect(await firstLogin, isTrue);
      expect(WindowCloseGuard.isBlocked, isTrue);
      secondResult.complete(Failure(Exception('cancelled')));
      expect(await secondLogin, isFalse);
      expect(WindowCloseGuard.isBlocked, isFalse);
      first.dispose();
      second.dispose();
    },
  );
}
