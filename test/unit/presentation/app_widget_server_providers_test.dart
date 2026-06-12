import 'package:backup_database/presentation/app_widget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackupDatabaseApp server-mode providers', () {
    test('includes ConnectionLogProvider in common providers', () {
      const app = BackupDatabaseApp();
      final hasConnectionLogProvider = app.debugCommonProviders().any(
        (provider) => provider.toString().contains('ConnectionLogProvider'),
      );

      expect(hasConnectionLogProvider, isTrue);
    });

    test('does not place ConnectionLogProvider in client-only providers', () {
      const app = BackupDatabaseApp();
      final hasConnectionLogProvider = app.debugClientOnlyProviders().any(
        (provider) => provider.toString().contains('ConnectionLogProvider'),
      );

      expect(hasConnectionLogProvider, isFalse);
    });

    test('server-mode provider tree includes ConnectionLogProvider', () {
      const app = BackupDatabaseApp();
      final hasConnectionLogProvider = app.debugProvidersForServerMode().any(
        (provider) => provider.toString().contains('ConnectionLogProvider'),
      );

      expect(hasConnectionLogProvider, isTrue);
    });

    test('server-mode tree keeps client-only providers out of common list', () {
      const app = BackupDatabaseApp();
      final commonDescriptions = app
          .debugCommonProviders()
          .map((provider) => provider.toString())
          .join('\n');

      expect(commonDescriptions, contains('ConnectionLogProvider'));
      expect(commonDescriptions, isNot(contains('ServerConnectionProvider')));
    });
  });
}
