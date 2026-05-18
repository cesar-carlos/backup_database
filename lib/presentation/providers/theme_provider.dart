import 'dart:async';

import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/boot/windows_native_chrome_bootstrap.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:system_theme/system_theme.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider({required IUserPreferencesRepository userPreferencesRepository})
    : _userPreferences = userPreferencesRepository;

  final IUserPreferencesRepository _userPreferences;

  bool _isDarkMode = false;
  bool _isInitialized = false;
  bool _useSystemAccentColor = false;
  // ignore: cancel_subscriptions -- cleared in dispose and when turning off system accent
  StreamSubscription<SystemAccentColor>? _accentSubscription;

  bool get isDarkMode => _isDarkMode;

  bool get useSystemAccentColor => _useSystemAccentColor;

  AccentColor get fluentAccentColor {
    if (!_useSystemAccentColor) {
      return AppTheme.brandFluentAccent;
    }
    final s = SystemTheme.accentColor;
    return AccentColor('normal', {
      'normal': s.accent,
      'dark': s.dark,
      'light': s.light,
    });
  }

  @override
  void dispose() {
    final sub = _accentSubscription;
    _accentSubscription = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      _isDarkMode = await _userPreferences.getDarkMode();
      _useSystemAccentColor = await _userPreferences.getUseSystemAccentColor();
      await SystemTheme.accentColor.load();
      await _attachAccentStreamIfNeeded();
      _isInitialized = true;
      notifyListeners();
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar preferência de tema', e, s);
      _isDarkMode = false;
      _useSystemAccentColor = false;
      _isInitialized = true;
    }
  }

  Future<void> _attachAccentStreamIfNeeded() async {
    final previous = _accentSubscription;
    _accentSubscription = null;
    if (previous != null) {
      await previous.cancel();
    }
    if (!_useSystemAccentColor) {
      return;
    }
    _accentSubscription = SystemTheme.onChange.listen((_) {
      if (_useSystemAccentColor) {
        notifyListeners();
      }
    });
  }

  Future<void> toggleTheme() async {
    await setDarkMode(!_isDarkMode);
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    notifyListeners();
    unawaited(
      WindowsNativeChromeBootstrap.syncMicaDarkAppearanceIfActive(value),
    );

    try {
      await _userPreferences.setDarkMode(value);
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao salvar preferência de tema', e, s);
    }
  }

  Future<void> setUseSystemAccentColor(bool value) async {
    _useSystemAccentColor = value;
    notifyListeners();

    try {
      await _userPreferences.setUseSystemAccentColor(value);
      if (value) {
        await SystemTheme.accentColor.load();
      }
      await _attachAccentStreamIfNeeded();
      notifyListeners();
    } on Object catch (e, s) {
      LoggerService.warning(
        'Erro ao salvar preferência de accent do sistema',
        e,
        s,
      );
    }
  }
}
