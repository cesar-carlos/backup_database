import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserPreferencesRepository implements IUserPreferencesRepository {
  static const String _minimizeToTrayKey = 'minimize_to_tray';
  static const String _closeToTrayKey = 'close_to_tray';
  static const String _darkModeKey = 'dark_mode';
  static const String _useWindowsMicaBackdropKey = 'use_windows_mica_backdrop';
  static const String _useSystemAccentColorKey = 'use_system_accent_color';
  static const String _uiDensityKey = 'ui_density';
  static const String _skeletonLoadingEnabledKey = 'skeleton_loading_enabled';
  static const String _localScheduleTimerEnabledKey =
      'local_schedule_timer_enabled';
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
  Future<bool> getUseWindowsMicaBackdrop() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useWindowsMicaBackdropKey) ?? true;
  }

  @override
  Future<void> setUseWindowsMicaBackdrop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useWindowsMicaBackdropKey, value);
  }

  @override
  Future<bool> getUseSystemAccentColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useSystemAccentColorKey) ?? false;
  }

  @override
  Future<void> setUseSystemAccentColor(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useSystemAccentColorKey, value);
  }

  @override
  Future<String?> getUiDensity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_uiDensityKey);
  }

  @override
  Future<void> setUiDensity(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_uiDensityKey, name);
  }

  @override
  Future<bool> getSkeletonLoadingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_skeletonLoadingEnabledKey) ?? true;
  }

  @override
  Future<void> setSkeletonLoadingEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_skeletonLoadingEnabledKey, value);
  }

  @override
  Future<bool> getLocalScheduleTimerEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_localScheduleTimerEnabledKey) ?? true;
  }

  @override
  Future<void> setLocalScheduleTimerEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localScheduleTimerEnabledKey, value);
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
