import 'package:backup_database/presentation/boot/service_account_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceAccountProbe.isSupportedSilentUpdateServiceAccount', () {
    test('accepts LocalSystem variations regardless of casing', () {
      expect(
        ServiceAccountProbe.isSupportedSilentUpdateServiceAccount(
          'LocalSystem',
        ),
        isTrue,
      );
      expect(
        ServiceAccountProbe.isSupportedSilentUpdateServiceAccount('System'),
        isTrue,
      );
      expect(
        ServiceAccountProbe.isSupportedSilentUpdateServiceAccount(
          r'NT AUTHORITY\System',
        ),
        isTrue,
      );
      expect(
        ServiceAccountProbe.isSupportedSilentUpdateServiceAccount(
          '  localsystem  ',
        ),
        isTrue,
      );
    });

    test('rejects custom user accounts', () {
      expect(
        ServiceAccountProbe.isSupportedSilentUpdateServiceAccount(
          r'.\BackupUser',
        ),
        isFalse,
      );
      expect(
        ServiceAccountProbe.isSupportedSilentUpdateServiceAccount(
          r'DOMAIN\ServiceAcc',
        ),
        isFalse,
      );
    });

    test('rejects null or empty input', () {
      expect(
        ServiceAccountProbe.isSupportedSilentUpdateServiceAccount(null),
        isFalse,
      );
      expect(
        ServiceAccountProbe.isSupportedSilentUpdateServiceAccount('   '),
        isFalse,
      );
    });
  });

  group('ServiceAccountProbe.buildUnsupportedServiceAccountMessage', () {
    test('returns null for supported accounts', () {
      expect(
        ServiceAccountProbe.buildUnsupportedServiceAccountMessage(
          'LocalSystem',
        ),
        isNull,
      );
    });

    test('returns actionable message for unsupported account', () {
      final msg = ServiceAccountProbe.buildUnsupportedServiceAccountMessage(
        r'DOMAIN\BackupUser',
      );

      expect(msg, isNotNull);
      expect(msg, contains(r'DOMAIN\BackupUser'));
      expect(msg, contains('LocalSystem'));
    });

    test('returns degraded message when account is unknown', () {
      final msg = ServiceAccountProbe.buildUnsupportedServiceAccountMessage(
        null,
      );

      expect(msg, contains('não foi possível validar'));
    });
  });
}
