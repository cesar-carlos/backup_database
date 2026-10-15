import 'dart:convert';
import 'dart:math';

import 'package:backup_database/core/security/password_hasher.dart';
import 'package:crypto/crypto.dart';

class AuthChallenge {
  AuthChallenge._();

  static const int nonceBytes = 32;

  static String createNonce([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(
      nonceBytes,
      (_) => source.nextInt(256),
      growable: false,
    );
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// HMAC-SHA256 of [nonce] keyed by the stored password hash.
  static String responseFor({
    required String nonce,
    required String passwordHash,
  }) {
    final hmac = Hmac(sha256, utf8.encode(passwordHash));
    return hmac.convert(utf8.encode(nonce)).toString();
  }

  static bool verify({
    required String nonce,
    required String passwordHash,
    required String response,
  }) {
    final expected = responseFor(nonce: nonce, passwordHash: passwordHash);
    return PasswordHasher.constantTimeEquals(expected, response);
  }
}
