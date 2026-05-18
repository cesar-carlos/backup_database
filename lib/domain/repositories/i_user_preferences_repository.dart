abstract class IUserPreferencesRepository {
  Future<void> ensureTrayDefaults();

  Future<bool> getMinimizeToTray();

  Future<void> setMinimizeToTray(bool value);

  Future<bool> getCloseToTray();

  Future<void> setCloseToTray(bool value);

  Future<bool> getDarkMode();

  Future<void> setDarkMode(bool value);

  Future<bool> getUseWindowsMicaBackdrop();

  Future<void> setUseWindowsMicaBackdrop(bool value);

  Future<bool> getUseSystemAccentColor();

  Future<void> setUseSystemAccentColor(bool value);

  /// Stored enum name: `compact`, `comfortable`, `spacious`; `null` = default.
  Future<String?> getUiDensity();

  Future<void> setUiDensity(String name);

  /// When `false`, list-heavy loading states use static placeholders without
  /// shimmer animation (accessibility).
  Future<bool> getSkeletonLoadingEnabled();

  Future<void> setSkeletonLoadingEnabled(bool value);

  Future<String?> getR1MultiProfileLegacyHintLastDismissedSignature();

  Future<void> setR1MultiProfileLegacyHintLastDismissedSignature(
    String signature,
  );
}
