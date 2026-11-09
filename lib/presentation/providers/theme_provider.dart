import 'dart:async';

import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/boot/windows_native_chrome_bootstrap.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:system_theme/system_theme.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider({
    required IUserPreferencesRepository userPreferencesRepository,
    Future<void> Function()? loadSystemAccentColor,
    Stream<SystemAccentColor>? accentChanges,
  }) : _userPreferences = userPreferencesRepository,
       _loadSystemAccentColor =
           loadSystemAccentColor ?? SystemTheme.accentColor.load,
       _accentChanges = accentChanges ?? SystemTheme.onChange;

  final IUserPreferencesRepository _userPreferences;
  final Future<void> Function() _loadSystemAccentColor;
  final Stream<SystemAccentColor> _accentChanges;
  bool _disposed = false;
  int _darkRevision = 0;
  int _accentRevision = 0;
  Future<void>? _initialization;
  Future<void> _operations = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _operations.then((_) => action());
    _operations = operation.catchError((Object _) {});
    return operation;
  }

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
    _disposed = true;
    final sub = _accentSubscription;
    _accentSubscription = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }

  Future<void> initialize() {
    if (_isInitialized || _disposed) return Future<void>.value();
    final darkRevision = _darkRevision;
    final accentRevision = _accentRevision;
    return _initialization ??= _enqueue(
      () => _initialize(darkRevision, accentRevision),
    ).whenComplete(() => _initialization = null);
  }

  Future<void> _initialize(int darkRevision, int accentRevision) async {
    if (_disposed) return;
    try {
      final dark = await _userPreferences.getDarkMode();
      final accent = await _userPreferences.getUseSystemAccentColor();
      if (_disposed) return;
      if (darkRevision == _darkRevision) _isDarkMode = dark;
      if (accentRevision == _accentRevision) _useSystemAccentColor = accent;
      if (_useSystemAccentColor) await _loadAccentSafely();
      await _attachAccentStreamIfNeeded();
      if (_disposed) return;
      _isInitialized = true;
      notifyListeners();
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar preferência de tema', e, s);
    }
  }

  Future<void> _loadAccentSafely() async {
    try {
      await _loadSystemAccentColor();
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar cor do sistema', e, s);
    }
  }

  Future<void> _attachAccentStreamIfNeeded() async {
    final previous = _accentSubscription;
    _accentSubscription = null;
    if (previous != null) {
      await previous.cancel();
    }
    if (_disposed || !_useSystemAccentColor) {
      return;
    }
    _accentSubscription = _accentChanges.listen((_) {
      if (!_disposed && _useSystemAccentColor) {
        notifyListeners();
      }
    });
  }

  Future<void> toggleTheme() async {
    await setDarkMode(!_isDarkMode);
  }

  Future<void> setDarkMode(bool value) async {
    if (_disposed) return;
    _darkRevision++;
    _isDarkMode = value;
    notifyListeners();
    unawaited(
      WindowsNativeChromeBootstrap.syncMicaDarkAppearanceIfActive(value),
    );

    try {
      await _enqueue(() => _userPreferences.setDarkMode(value));
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao salvar preferência de tema', e, s);
    }
  }

  Future<void> setUseSystemAccentColor(bool value) async {
    if (_disposed) return;
    final revision = ++_accentRevision;
    _useSystemAccentColor = value;
    notifyListeners();

    try {
      await _enqueue(() async {
        await _userPreferences.setUseSystemAccentColor(value);
        if (_disposed || revision != _accentRevision) return;
        if (value) await _loadAccentSafely();
        if (_disposed || revision != _accentRevision) return;
        await _attachAccentStreamIfNeeded();
        if (!_disposed) notifyListeners();
      });
    } on Object catch (e, s) {
      LoggerService.warning(
        'Erro ao salvar preferência de accent do sistema',
        e,
        s,
      );
    }
  }
}
