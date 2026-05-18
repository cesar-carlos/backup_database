import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/providers/skeleton_loading_preference_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SkeletonLoadingPreferenceProvider', () {
    late _FakeUserPreferencesRepository prefs;
    late SkeletonLoadingPreferenceProvider provider;

    setUp(() {
      prefs = _FakeUserPreferencesRepository();
      provider = SkeletonLoadingPreferenceProvider(
        userPreferencesRepository: prefs,
      );
    });

    test('initialize loads flag from repository', () async {
      prefs.skeletonLoadingEnabled = false;

      await provider.initialize();

      expect(provider.shimmerLoadingEffectsEnabled, isFalse);
    });

    test(
      'setShimmerLoadingEffectsEnabled updates state and persists',
      () async {
        await provider.initialize();

        await provider.setShimmerLoadingEffectsEnabled(false);

        expect(provider.shimmerLoadingEffectsEnabled, isFalse);
        expect(prefs.skeletonLoadingEnabled, isFalse);
      },
    );
  });
}

class _FakeUserPreferencesRepository implements IUserPreferencesRepository {
  bool skeletonLoadingEnabled = true;

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
  Future<String?> getUiDensity() async => null;

  @override
  Future<bool> getSkeletonLoadingEnabled() async => skeletonLoadingEnabled;

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
  Future<void> setUiDensity(String name) async {}

  @override
  Future<void> setSkeletonLoadingEnabled(bool value) async {
    skeletonLoadingEnabled = value;
  }

  @override
  Future<bool> getUseSystemAccentColor() async => false;

  @override
  Future<bool> getUseWindowsMicaBackdrop() async => true;

  @override
  Future<void> setUseSystemAccentColor(bool value) async {}

  @override
  Future<void> setUseWindowsMicaBackdrop(bool value) async {}

  @override
  Future<bool> getLocalScheduleTimerEnabled() async => true;

  @override
  Future<void> setLocalScheduleTimerEnabled(bool value) async {}
}
