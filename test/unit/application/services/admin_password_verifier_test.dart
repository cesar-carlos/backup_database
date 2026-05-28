import 'package:backup_database/application/services/admin_password_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminPasswordVerifier.encodeForStorage', () {
    test('produces parseable pbkdf2 hash that verifies the same password', () {
      const password = 'minhaSenhaForte!2026';
      final encoded = AdminPasswordVerifier.encodeForStorage(
        password: password,
        iterations: 1000, // pequeno só para o teste
      );

      expect(encoded, startsWith(r'pbkdf2-sha256$1000$'));
      expect(encoded.split(r'$'), hasLength(4));

      final verifier = AdminPasswordVerifier();
      final result = verifier.verify(
        enteredPassword: password,
        storedHash: encoded,
      );
      expect(result.isSuccess, isTrue);
    });

    test('different salts produce different hashes for same password', () {
      const password = 'duplaSenha';
      final a = AdminPasswordVerifier.encodeForStorage(
        password: password,
        iterations: 1000,
      );
      final b = AdminPasswordVerifier.encodeForStorage(
        password: password,
        iterations: 1000,
      );
      expect(a, isNot(b));
    });
  });

  group('AdminPasswordVerifier.verify — wrong password', () {
    test('returns invalidPassword with remaining attempts counter', () {
      final hash = AdminPasswordVerifier.encodeForStorage(
        password: 'correta',
        iterations: 1000,
      );
      final verifier = AdminPasswordVerifier();

      final r1 = verifier.verify(
        enteredPassword: 'errada',
        storedHash: hash,
      );
      expect(r1.isInvalidPassword, isTrue);
      expect(r1.detail, 2);

      final r2 = verifier.verify(
        enteredPassword: 'errada',
        storedHash: hash,
      );
      expect(r2.isInvalidPassword, isTrue);
      expect(r2.detail, 1);
    });

    test('locks after maxAttempts and refuses even correct password', () {
      final hash = AdminPasswordVerifier.encodeForStorage(
        password: 'correta',
        iterations: 1000,
      );
      var fakeNow = DateTime(2026);
      final verifier = AdminPasswordVerifier(
        maxAttempts: 2,
        now: () => fakeNow,
      );

      // 1ª errada → invalida
      verifier.verify(enteredPassword: 'errada', storedHash: hash);
      // 2ª errada → lockout
      final third = verifier.verify(
        enteredPassword: 'errada',
        storedHash: hash,
      );
      expect(third.isLockedOut, isTrue);

      // 3ª (mesmo correta) → ainda lockada
      final fourth = verifier.verify(
        enteredPassword: 'correta',
        storedHash: hash,
      );
      expect(fourth.isLockedOut, isTrue);

      // Avança o tempo passado o lockout → aceita correta
      fakeNow = fakeNow.add(const Duration(seconds: 31));
      final fifth = verifier.verify(
        enteredPassword: 'correta',
        storedHash: hash,
      );
      expect(fifth.isSuccess, isTrue);
    });

    test('success resets failed attempts counter', () {
      final hash = AdminPasswordVerifier.encodeForStorage(
        password: 'correta',
        iterations: 1000,
      );
      final verifier = AdminPasswordVerifier();

      verifier.verify(enteredPassword: 'errada', storedHash: hash);
      verifier.verify(enteredPassword: 'correta', storedHash: hash);
      final r = verifier.verify(enteredPassword: 'errada', storedHash: hash);
      // Deve ser 2 (3 - 1), não 1.
      expect(r.isInvalidPassword, isTrue);
      expect(r.detail, 2);
    });
  });

  group('AdminPasswordVerifier.verify — config', () {
    test('empty hash returns notConfigured', () {
      final verifier = AdminPasswordVerifier();
      final r = verifier.verify(
        enteredPassword: 'qualquer',
        storedHash: '',
      );
      expect(r.isNotConfigured, isTrue);
    });

    test('malformed hash returns notConfigured', () {
      final verifier = AdminPasswordVerifier();
      final r = verifier.verify(
        enteredPassword: 'qualquer',
        storedHash: 'formato-invalido',
      );
      expect(r.isNotConfigured, isTrue);
    });

    test('hash with unsupported algorithm returns notConfigured', () {
      final verifier = AdminPasswordVerifier();
      final r = verifier.verify(
        enteredPassword: 'qualquer',
        storedHash: r'bcrypt-sha256$1000$AAAA$BBBB',
      );
      expect(r.isNotConfigured, isTrue);
    });
  });
}
