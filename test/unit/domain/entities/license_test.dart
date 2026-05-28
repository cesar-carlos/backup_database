import 'package:backup_database/domain/entities/license.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('License.isExpired / isNotYetValid / isValid', () {
    test('sem expiresAt nem notBefore → válida', () {
      final lic = License(
        deviceKey: 'd',
        licenseKey: 'k',
        allowedFeatures: const ['f'],
      );
      expect(lic.isExpired, isFalse);
      expect(lic.isNotYetValid, isFalse);
      expect(lic.isValid, isTrue);
    });

    test('expiresAt no passado → isExpired e !isValid', () {
      final lic = License(
        deviceKey: 'd',
        licenseKey: 'k',
        allowedFeatures: const ['f'],
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(lic.isExpired, isTrue);
      expect(lic.isValid, isFalse);
    });

    test('notBefore no futuro → isNotYetValid e !isValid', () {
      final lic = License(
        deviceKey: 'd',
        licenseKey: 'k',
        allowedFeatures: const ['f'],
        notBefore: DateTime.now().add(const Duration(days: 1)),
      );
      expect(lic.isExpired, isFalse);
      expect(lic.isNotYetValid, isTrue);
      expect(lic.isValid, isFalse);
    });

    test('notBefore no passado e expiresAt no futuro → válida', () {
      final lic = License(
        deviceKey: 'd',
        licenseKey: 'k',
        allowedFeatures: const ['f'],
        notBefore: DateTime.now().subtract(const Duration(days: 1)),
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      expect(lic.isValid, isTrue);
    });
  });

  group('License equality', () {
    test('mesma licenseKey + deviceKey → iguais (id diferente)', () {
      final a = License(
        id: 'a-id',
        deviceKey: 'd',
        licenseKey: 'same-key',
        allowedFeatures: const ['f'],
      );
      final b = License(
        id: 'b-id',
        deviceKey: 'd',
        licenseKey: 'same-key',
        allowedFeatures: const ['f', 'g'],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('licenseKey diferente → diferentes', () {
      final a = License(
        deviceKey: 'd',
        licenseKey: 'k1',
        allowedFeatures: const ['f'],
      );
      final b = License(
        deviceKey: 'd',
        licenseKey: 'k2',
        allowedFeatures: const ['f'],
      );
      expect(a, isNot(b));
    });

    test('deviceKey diferente → diferentes (mesmo licenseKey)', () {
      final a = License(
        deviceKey: 'd1',
        licenseKey: 'k',
        allowedFeatures: const ['f'],
      );
      final b = License(
        deviceKey: 'd2',
        licenseKey: 'k',
        allowedFeatures: const ['f'],
      );
      expect(a, isNot(b));
    });
  });

  group('License.copyWith', () {
    test('preserva notBefore quando não passado', () {
      final original = License(
        deviceKey: 'd',
        licenseKey: 'k',
        allowedFeatures: const ['f'],
        notBefore: DateTime(2026),
      );
      final copy = original.copyWith();
      expect(copy.notBefore, original.notBefore);
    });

    test('substitui notBefore quando passado', () {
      final original = License(
        deviceKey: 'd',
        licenseKey: 'k',
        allowedFeatures: const ['f'],
        notBefore: DateTime(2026),
      );
      final novo = DateTime(2027);
      final copy = original.copyWith(notBefore: novo);
      expect(copy.notBefore, novo);
    });
  });
}
