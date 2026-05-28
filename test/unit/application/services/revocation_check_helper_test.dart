import 'package:backup_database/application/services/revocation_check_helper.dart';
import 'package:backup_database/domain/services/i_revocation_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRevocationChecker extends Mock implements IRevocationChecker {}

class _ThrowingChecker implements IRevocationChecker {
  @override
  Future<bool> isRevoked(String deviceKey) async {
    throw StateError('CRL inaccessible');
  }
}

void main() {
  group('RevocationCheckHelper.isRevokedSafe', () {
    test('null checker → fail-open (false)', () async {
      final result = await RevocationCheckHelper.isRevokedSafe(
        null,
        'device-1',
      );
      expect(result, isFalse);
    });

    test('checker returning true → true', () async {
      final checker = _MockRevocationChecker();
      when(() => checker.isRevoked(any())).thenAnswer((_) async => true);

      final result = await RevocationCheckHelper.isRevokedSafe(
        checker,
        'device-1',
      );
      expect(result, isTrue);
    });

    test('checker returning false → false', () async {
      final checker = _MockRevocationChecker();
      when(() => checker.isRevoked(any())).thenAnswer((_) async => false);

      final result = await RevocationCheckHelper.isRevokedSafe(
        checker,
        'device-1',
      );
      expect(result, isFalse);
    });

    test('checker throwing → fail-open (false) sem propagar', () async {
      final result = await RevocationCheckHelper.isRevokedSafe(
        _ThrowingChecker(),
        'device-1',
      );
      expect(result, isFalse);
    });
  });
}
