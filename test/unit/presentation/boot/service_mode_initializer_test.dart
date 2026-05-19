import 'package:backup_database/presentation/boot/service_mode_initializer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceModeInitializer service account policy', () {
    test('accepts LocalSystem aliases', () {
      expect(
        ServiceModeInitializer.isSupportedSilentUpdateServiceAccount(
          'LocalSystem',
        ),
        isTrue,
      );
      expect(
        ServiceModeInitializer.isSupportedSilentUpdateServiceAccount('System'),
        isTrue,
      );
      expect(
        ServiceModeInitializer.isSupportedSilentUpdateServiceAccount(
          r'NT AUTHORITY\System',
        ),
        isTrue,
      );
    });

    test('blocks custom or unknown accounts with actionable message', () {
      expect(
        ServiceModeInitializer.buildUnsupportedServiceAccountMessage(
          r'.\BackupUser',
        ),
        contains('LocalSystem'),
      );
      expect(
        ServiceModeInitializer.buildUnsupportedServiceAccountMessage(null),
        contains('não foi possível validar'),
      );
    });
  });
}
