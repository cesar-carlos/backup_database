import 'package:backup_database/infrastructure/repositories/user_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('UserPreferencesRepository', () {
    late UserPreferencesRepository repository;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      repository = UserPreferencesRepository();
    });

    test('ensureTrayDefaults writes false when keys are absent', () async {
      await repository.ensureTrayDefaults();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('minimize_to_tray'), isFalse);
      expect(prefs.getBool('close_to_tray'), isFalse);
    });

    test('ensureTrayDefaults does not overwrite existing tray keys', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'minimize_to_tray': true,
        'close_to_tray': true,
      });
      repository = UserPreferencesRepository();

      await repository.ensureTrayDefaults();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('minimize_to_tray'), isTrue);
      expect(prefs.getBool('close_to_tray'), isTrue);
    });

    test('getMinimizeToTray and getCloseToTray default to false', () async {
      expect(await repository.getMinimizeToTray(), isFalse);
      expect(await repository.getCloseToTray(), isFalse);
    });

    test('setMinimizeToTray and setCloseToTray persist', () async {
      await repository.setMinimizeToTray(true);
      await repository.setCloseToTray(true);

      expect(await repository.getMinimizeToTray(), isTrue);
      expect(await repository.getCloseToTray(), isTrue);
    });

    test('getDarkMode defaults to false and setDarkMode persists', () async {
      expect(await repository.getDarkMode(), isFalse);
      await repository.setDarkMode(true);
      expect(await repository.getDarkMode(), isTrue);
    });

    test('getUseWindowsMicaBackdrop defaults to true when unset', () async {
      expect(await repository.getUseWindowsMicaBackdrop(), isTrue);
    });

    test('setUseWindowsMicaBackdrop persists', () async {
      await repository.setUseWindowsMicaBackdrop(false);
      expect(await repository.getUseWindowsMicaBackdrop(), isFalse);
    });

    test('getUseSystemAccentColor defaults to false when unset', () async {
      expect(await repository.getUseSystemAccentColor(), isFalse);
    });

    test('setUseSystemAccentColor persists', () async {
      await repository.setUseSystemAccentColor(true);
      expect(await repository.getUseSystemAccentColor(), isTrue);
    });

    test('getUiDensity returns null when unset', () async {
      expect(await repository.getUiDensity(), isNull);
    });

    test('setUiDensity persists', () async {
      await repository.setUiDensity('compact');
      expect(await repository.getUiDensity(), 'compact');
    });

    test('getSkeletonLoadingEnabled defaults to true when unset', () async {
      expect(await repository.getSkeletonLoadingEnabled(), isTrue);
    });

    test('setSkeletonLoadingEnabled persists', () async {
      await repository.setSkeletonLoadingEnabled(false);
      expect(await repository.getSkeletonLoadingEnabled(), isFalse);
    });

    test(
      'R1 multi-profile hint signature round-trip',
      () async {
        expect(
          await repository.getR1MultiProfileLegacyHintLastDismissedSignature(),
          isNull,
        );
        await repository.setR1MultiProfileLegacyHintLastDismissedSignature(
          'sig-a',
        );
        expect(
          await repository.getR1MultiProfileLegacyHintLastDismissedSignature(),
          'sig-a',
        );
      },
    );
  });
}
