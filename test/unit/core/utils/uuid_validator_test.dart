import 'package:backup_database/core/utils/uuid_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UuidValidator.isValid — valid UUIDs', () {
    test('accepts valid UUID v4 (lowercase)', () {
      expect(
        UuidValidator.isValid('6ba7b810-9dad-11d1-80b4-00c04fd430c8'),
        isTrue,
      );
    });

    test('accepts valid UUID v4 with mixed case', () {
      expect(
        UuidValidator.isValid('6BA7B810-9DAD-11D1-80B4-00C04FD430C8'),
        isTrue,
      );
    });

    test('accepts UUID v1 (version digit = 1)', () {
      expect(
        UuidValidator.isValid('550e8400-e29b-11d4-a716-446655440000'),
        isTrue,
      );
    });

    test('accepts UUID v5 (version digit = 5)', () {
      expect(
        UuidValidator.isValid('886313e1-3b8a-5372-9b90-0c9aee199e5d'),
        isTrue,
      );
    });
  });

  group('UuidValidator.isValid — invalid UUIDs', () {
    test('rejects empty string', () {
      expect(UuidValidator.isValid(''), isFalse);
    });

    test('rejects whitespace-only string', () {
      expect(UuidValidator.isValid('   '), isFalse);
    });

    test('rejects UUID without dashes', () {
      expect(
        UuidValidator.isValid('6ba7b8109dad11d180b400c04fd430c8'),
        isFalse,
      );
    });

    test('rejects UUID with wrong segment lengths', () {
      expect(
        UuidValidator.isValid('6ba7b81-9dad-11d1-80b4-00c04fd430c8'),
        isFalse,
        reason: 'first segment must be 8 chars',
      );
      expect(
        UuidValidator.isValid('6ba7b810-9dad-11d1-80b4-00c04fd430c'),
        isFalse,
        reason: 'last segment must be 12 chars',
      );
    });

    test('rejects non-hex characters', () {
      expect(
        UuidValidator.isValid('zba7b810-9dad-11d1-80b4-00c04fd430c8'),
        isFalse,
      );
    });

    test('rejects invalid version digit (0, 6, 7)', () {
      expect(
        UuidValidator.isValid('6ba7b810-9dad-01d1-80b4-00c04fd430c8'),
        isFalse,
        reason: 'version 0 not allowed',
      );
      expect(
        UuidValidator.isValid('6ba7b810-9dad-61d1-80b4-00c04fd430c8'),
        isFalse,
        reason: 'version 6 not in allowed range 1-5',
      );
    });

    test(
      'rejects invalid variant digit (must be 8/9/a/b for RFC 4122)',
      () {
        expect(
          UuidValidator.isValid('6ba7b810-9dad-41d1-00b4-00c04fd430c8'),
          isFalse,
          reason: 'variant must be 8/9/a/b',
        );
        expect(
          UuidValidator.isValid('6ba7b810-9dad-41d1-c0b4-00c04fd430c8'),
          isFalse,
        );
      },
    );

    test('rejects strings with leading or trailing whitespace', () {
      expect(
        UuidValidator.isValid(' 6ba7b810-9dad-11d1-80b4-00c04fd430c8'),
        isFalse,
        reason: 'no implicit trim — caller must trim if needed',
      );
      expect(
        UuidValidator.isValid('6ba7b810-9dad-11d1-80b4-00c04fd430c8 '),
        isFalse,
      );
    });

    test('rejects scheduleId-like prefix injection attempts', () {
      // Defensa contra entradas vindas de CLI args (--schedule-id=...)
      // que tentem injetar SQL ou path traversal — apenas formato UUID puro.
      expect(
        UuidValidator.isValid("'; DROP TABLE schedules; --"),
        isFalse,
      );
      expect(
        UuidValidator.isValid('../etc/passwd'),
        isFalse,
      );
    });
  });
}
