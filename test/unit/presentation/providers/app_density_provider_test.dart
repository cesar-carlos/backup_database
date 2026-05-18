import 'package:backup_database/core/theme/tokens/app_density.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/providers/app_density_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDensityProvider', () {
    late _FakeUserPreferencesRepository prefs;
    late AppDensityProvider provider;

    setUp(() {
      prefs = _FakeUserPreferencesRepository();
      provider = AppDensityProvider(userPreferencesRepository: prefs);
    });

    test('initialize maps stored name to density', () async {
      prefs.uiDensity = 'compact';

      await provider.initialize();

      expect(provider.density, AppDensity.compact);
    });

    test('initialize uses comfortable for unknown stored value', () async {
      prefs.uiDensity = 'unknown';

      await provider.initialize();

      expect(provider.density, AppDensity.comfortable);
    });

    test('setDensity updates state and persists', () async {
      await provider.initialize();

      await provider.setDensity(AppDensity.spacious);

      expect(provider.density, AppDensity.spacious);
      expect(prefs.uiDensity, 'spacious');
    });
  });
}

class _FakeUserPreferencesRepository implements IUserPreferencesRepository {
  String? uiDensity;

  @override
  Future<void> ensureTrayDefaults() async {}

  @override
  Future<bool> getCloseToTray() async => false;

  @override
  Future<bool> getDarkMode() async => false;

  @override
  Future<bool> getMinimizeToTray() async => false;

  @override
  Future<String?> getR1MultiProfileLegacyHintLastDismissedSignature() async =>
      null;

  @override
  Future<String?> getUiDensity() async => uiDensity;

  @override
  Future<void> setCloseToTray(bool value) async {}

  @override
  Future<void> setDarkMode(bool value) async {}

  @override
  Future<void> setMinimizeToTray(bool value) async {}

  @override
  Future<void> setR1MultiProfileLegacyHintLastDismissedSignature(
    String signature,
  ) async {}

  @override
  Future<void> setUiDensity(String name) async {
    uiDensity = name;
  }

  @override
  Future<bool> getSkeletonLoadingEnabled() async => true;

  @override
  Future<void> setSkeletonLoadingEnabled(bool value) async {}

  @override
  Future<bool> getUseSystemAccentColor() async => false;

  @override
  Future<bool> getUseWindowsMicaBackdrop() async => true;

  @override
  Future<void> setUseSystemAccentColor(bool value) async {}

  @override
  Future<void> setUseWindowsMicaBackdrop(bool value) async {}
}
