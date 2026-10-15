import 'dart:math';

import 'package:backup_database/core/security/auth_challenge.dart';
import 'package:backup_database/core/security/password_hasher.dart';
import 'package:backup_database/infrastructure/protocol/auth_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthChallenge', () {
    test('response matches on both sides for the same nonce and hash', () {
      const nonce = 'abc123';
      final passwordHash = PasswordHasher.hash('secret', 'server-1');
      final first = AuthChallenge.responseFor(
        nonce: nonce,
        passwordHash: passwordHash,
      );
      final second = AuthChallenge.responseFor(
        nonce: nonce,
        passwordHash: passwordHash,
      );

      expect(
        AuthChallenge.verify(
          nonce: nonce,
          passwordHash: passwordHash,
          response: first,
        ),
        isTrue,
      );
      expect(first, second);
    });

    test('rejects a tampered response or a different password hash', () {
      const nonce = 'abc123';
      final passwordHash = PasswordHasher.hash('secret', 'server-1');
      final response = AuthChallenge.responseFor(
        nonce: nonce,
        passwordHash: passwordHash,
      );

      expect(
        AuthChallenge.verify(
          nonce: nonce,
          passwordHash: passwordHash,
          response: '${response.substring(0, response.length - 1)}0',
        ),
        isFalse,
      );
      expect(
        AuthChallenge.verify(
          nonce: nonce,
          passwordHash: PasswordHasher.hash('other', 'server-1'),
          response: response,
        ),
        isFalse,
      );
    });

    test('createNonce is 32 bytes of hex and is not reused', () {
      final random = Random(7);
      final first = AuthChallenge.createNonce(random);
      final second = AuthChallenge.createNonce(random);

      expect(first, hasLength(AuthChallenge.nonceBytes * 2));
      expect(first, isNot(second));
    });

    test(
      'challenge request carries serverId and the response carries the nonce',
      () {
        final request = createAuthChallengeRequest(serverId: 'srv-1');
        expect(isAuthChallengeRequest(request), isTrue);

        final challenge = createAuthChallenge(nonce: 'nonce-1');
        final auth = createChallengeAuthRequest(
          challenge: challenge,
          serverId: 'srv-1',
          password: 'secret',
        );

        expect(auth, isNotNull);
        expect(getAuthRequestNonce(auth!), 'nonce-1');
        expect(
          auth.payload['passwordHash'],
          AuthChallenge.responseFor(
            nonce: 'nonce-1',
            passwordHash: PasswordHasher.hash('secret', 'srv-1'),
          ),
        );
      },
    );
  });
}
