import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _darkModeKey = 'dark_mode';
  bool _isDarkMode = false;
  bool _isInitialized = false;

  bool get isDarkMode => _isDarkMode;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_darkModeKey) ?? false;
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_darkModeKey, value);
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao salvar preferência de tema', e, s);
    }
  }
}
