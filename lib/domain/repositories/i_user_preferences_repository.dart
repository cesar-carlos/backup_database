abstract class IUserPreferencesRepository {
  Future<void> ensureTrayDefaults();

  Future<bool> getMinimizeToTray();

  Future<void> setMinimizeToTray(bool value);

  Future<bool> getCloseToTray();

  Future<void> setCloseToTray(bool value);

  Future<bool> getDarkMode();

  Future<void> setDarkMode(bool value);

  Future<String?> getR1MultiProfileLegacyHintLastDismissedSignature();

  Future<void> setR1MultiProfileLegacyHintLastDismissedSignature(
    String signature,
  );
}
