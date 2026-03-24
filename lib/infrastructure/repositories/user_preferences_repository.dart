import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserPreferencesRepository implements IUserPreferencesRepository {
  static const String _minimizeToTrayKey = 'minimize_to_tray';
  static const String _closeToTrayKey = 'close_to_tray';
  static const String _darkModeKey = 'dark_mode';
  static const String _r1MultiProfileLegacyHintDismissedSigKey =
      'r1_multi_profile_legacy_hint_dismissed_sig';

  @override
  Future<void> ensureTrayDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_minimizeToTrayKey)) {
      await prefs.setBool(_minimizeToTrayKey, false);
    }
    if (!prefs.containsKey(_closeToTrayKey)) {
      await prefs.setBool(_closeToTrayKey, false);
    }
  }

  @override
  Future<bool> getMinimizeToTray() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_minimizeToTrayKey) ?? false;
  }

  @override
  Future<void> setMinimizeToTray(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_minimizeToTrayKey, value);
  }

  @override
  Future<bool> getCloseToTray() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_closeToTrayKey) ?? false;
  }

  @override
  Future<void> setCloseToTray(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_closeToTrayKey, value);
  }

  @override
  Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkModeKey) ?? false;
  }

  @override
  Future<void> setDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, value);
  }

  @override
  Future<String?> getR1MultiProfileLegacyHintLastDismissedSignature() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_r1MultiProfileLegacyHintDismissedSigKey);
  }

  @override
  Future<void> setR1MultiProfileLegacyHintLastDismissedSignature(
    String signature,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_r1MultiProfileLegacyHintDismissedSigKey, signature);
  }
}
