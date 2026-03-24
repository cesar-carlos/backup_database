import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:flutter/foundation.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider({required IUserPreferencesRepository userPreferencesRepository})
    : _userPreferences = userPreferencesRepository;

  final IUserPreferencesRepository _userPreferences;

  bool _isDarkMode = false;
  bool _isInitialized = false;

  bool get isDarkMode => _isDarkMode;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      _isDarkMode = await _userPreferences.getDarkMode();
      _isInitialized = true;
      notifyListeners();
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar preferência de tema', e, s);
      _isDarkMode = false;
      _isInitialized = true;
    }
  }

  Future<void> toggleTheme() async {
    await setDarkMode(!_isDarkMode);
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    notifyListeners();

    try {
      await _userPreferences.setDarkMode(value);
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao salvar preferência de tema', e, s);
    }
  }
}
