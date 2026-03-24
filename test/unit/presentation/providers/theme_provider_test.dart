import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/providers/theme_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeProvider', () {
    late _FakeUserPreferencesRepository prefs;
    late ThemeProvider provider;

    setUp(() {
      prefs = _FakeUserPreferencesRepository();
      provider = ThemeProvider(userPreferencesRepository: prefs);
    });

    test('initialize loads dark mode from repository', () async {
      prefs.darkMode = true;

      await provider.initialize();

      expect(provider.isDarkMode, isTrue);
    });

    test('initialize is idempotent', () async {
      prefs.darkMode = true;
      await provider.initialize();
      prefs.darkMode = false;

      await provider.initialize();

      expect(provider.isDarkMode, isTrue);
    });

    test('setDarkMode updates state and persists', () async {
      await provider.initialize();

      await provider.setDarkMode(true);

      expect(provider.isDarkMode, isTrue);
      expect(prefs.darkMode, isTrue);
    });

    test('toggleTheme flips mode', () async {
      await provider.initialize();
      expect(provider.isDarkMode, isFalse);

      await provider.toggleTheme();

      expect(provider.isDarkMode, isTrue);
      expect(prefs.darkMode, isTrue);
    });
  });
}

class _FakeUserPreferencesRepository implements IUserPreferencesRepository {
  bool darkMode = false;
  bool minimizeToTray = false;
  bool closeToTray = false;
  String? r1Signature;

  @override
  Future<void> ensureTrayDefaults() async {}

  @override
  Future<bool> getCloseToTray() async => closeToTray;

  @override
  Future<bool> getDarkMode() async => darkMode;

  @override
  Future<bool> getMinimizeToTray() async => minimizeToTray;

  @override
  Future<String?> getR1MultiProfileLegacyHintLastDismissedSignature() async =>
      r1Signature;

  @override
  Future<void> setCloseToTray(bool value) async {
    closeToTray = value;
  }

  @override
  Future<void> setDarkMode(bool value) async {
    darkMode = value;
  }

  @override
  Future<void> setMinimizeToTray(bool value) async {
    minimizeToTray = value;
  }

  @override
  Future<void> setR1MultiProfileLegacyHintLastDismissedSignature(
    String signature,
  ) async {
    r1Signature = signature;
  }
}
