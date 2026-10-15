import 'dart:io';

import 'package:backup_database/core/l10n/app_ui_locale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAppUiLocale', () {
    test('should use Portuguese when the installer chose it', () {
      final locale = resolveAppUiLocale(
        installerCode: 'pt',
        platformLocaleName: 'en_US',
      );

      expect(locale, appUiLocalePortuguese);
    });

    test('should use English when the installer chose it', () {
      final locale = resolveAppUiLocale(
        installerCode: 'english',
        platformLocaleName: 'pt_BR',
      );

      expect(locale, appUiLocaleEnglish);
    });

    test('should follow a Portuguese platform when nothing was saved', () {
      final locale = resolveAppUiLocale(
        platformLocaleName: 'pt-BR',
      );

      expect(locale, appUiLocalePortuguese);
    });

    test('should fall back to English for an unknown locale', () {
      final locale = resolveAppUiLocale(
        installerCode: 'fr',
        platformLocaleName: 'de_DE',
      );

      expect(locale, appUiLocaleEnglish);
    });
  });

  group('readInstalledUiLocaleCode', () {
    test('should read the code saved by the installer', () {
      final dir = Directory.systemTemp.createTempSync(
        'ui_locale_test_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}\\ui_locale');
      file.writeAsStringSync('pt\n');

      expect(readInstalledUiLocaleCode(path: file.path), 'pt');
    });

    test('should return null when the file is missing', () {
      expect(
        readInstalledUiLocaleCode(
          path: '${Directory.systemTemp.path}\\missing_ui_locale_code',
        ),
        isNull,
      );
    });
  });
}
