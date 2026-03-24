import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/presentation/managers/window_manager_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class SystemSettingsProvider extends ChangeNotifier {
  SystemSettingsProvider({
    WindowManagerService? windowManager,
    ProcessRunner? processRunner,
    String Function()? executablePathProvider,
  }) : _windowManager = windowManager ?? WindowManagerService(),
       _processRunner = processRunner ?? Process.run,
       _executablePathProvider =
           executablePathProvider ?? (() => Platform.resolvedExecutable);
  final WindowManagerService _windowManager;
  final ProcessRunner _processRunner;
  final String Function() _executablePathProvider;

  static const String _minimizeToTrayKey = 'minimize_to_tray';
  static const String _closeToTrayKey = 'close_to_tray';
  static const String _startMinimizedKey = 'start_minimized';
  static const String _startWithWindowsKey = 'start_with_windows';

  bool _minimizeToTray = false;
  bool _closeToTray = false;
  bool _startMinimized = false;
  bool _startWithWindows = false;
  bool _isInitialized = false;

  bool get minimizeToTray => _minimizeToTray;
  bool get closeToTray => _closeToTray;
  bool get startMinimized => _startMinimized;
  bool get startWithWindows => _startWithWindows;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final isFirstRun =
          !prefs.containsKey(_minimizeToTrayKey) &&
          !prefs.containsKey(_closeToTrayKey) &&
          !prefs.containsKey(_startMinimizedKey) &&
          !prefs.containsKey(_startWithWindowsKey);

      _minimizeToTray = prefs.getBool(_minimizeToTrayKey) ?? false;
      _closeToTray = prefs.getBool(_closeToTrayKey) ?? false;
      _startMinimized = prefs.getBool(_startMinimizedKey) ?? false;
      _startWithWindows = prefs.getBool(_startWithWindowsKey) ?? false;

      if (isFirstRun) {
        await prefs.setBool(_minimizeToTrayKey, _minimizeToTray);
        await prefs.setBool(_closeToTrayKey, _closeToTray);
        await prefs.setBool(_startMinimizedKey, _startMinimized);
        await prefs.setBool(_startWithWindowsKey, _startWithWindows);
        LoggerService.info('Primeira inicialização - valores padrão salvos');
      }

      if (_startWithWindows) {
        await _updateStartWithWindows(true);
      }

      _isInitialized = true;

      _windowManager.setMinimizeToTray(_minimizeToTray);
      _windowManager.setCloseToTray(_closeToTray);

      LoggerService.info(
        'Configurações aplicadas - Minimizar para bandeja: $_minimizeToTray, Fechar para bandeja: $_closeToTray',
      );

      notifyListeners();
      LoggerService.info('Configurações do sistema carregadas');
    } on Object catch (e) {
      LoggerService.error('Erro ao carregar configurações do sistema', e);
      _isInitialized = true;
    }
  }

  Future<void> setMinimizeToTray(bool value) async {
    _minimizeToTray = value;
    _windowManager.setMinimizeToTray(value);
    notifyListeners();
    LoggerService.debug('Minimizar para bandeja alterado: $value');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_minimizeToTrayKey, value);
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configuração minimizeToTray', e);
    }
  }

  Future<void> setCloseToTray(bool value) async {
    _closeToTray = value;
    _windowManager.setCloseToTray(value);
    notifyListeners();
    LoggerService.debug('Fechar para bandeja alterado: $value');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_closeToTrayKey, value);
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configuração closeToTray', e);
    }
  }

  Future<void> setStartMinimized(bool value) async {
    _startMinimized = value;
    notifyListeners();
    LoggerService.debug('Iniciar minimizado alterado: $value');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_startMinimizedKey, value);

      if (_startWithWindows) {
        await _updateStartWithWindows(true);
      }
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configuração startMinimized', e);
    }
  }

  Future<void> setStartWithWindows(bool value) async {
    _startWithWindows = value;
    await _updateStartWithWindows(value);
    notifyListeners();
    LoggerService.debug('Iniciar com Windows alterado: $value');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_startWithWindowsKey, value);
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configuração startWithWindows', e);
    }
  }

  Future<void> _updateStartWithWindows(bool enable) async {
    try {
      final executablePath = _executablePathProvider();

      if (enable) {
        final prefs = await SharedPreferences.getInstance();
        final startMinimized = prefs.getBool(_startMinimizedKey) ?? false;

        const startupArg = SingleInstanceConfig.startupLaunchArgument;
        const minimizedArg = SingleInstanceConfig.minimizedArgument;
        final command = startMinimized
            ? '"$executablePath" $minimizedArg $startupArg'
            : '"$executablePath" $startupArg';

        final result = await _processRunner('reg', [
          'add',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          'BackupDatabase',
          '/t',
          'REG_SZ',
          '/d',
          command,
          '/f',
        ]);

        if (result.exitCode == 0) {
          LoggerService.info(
            'Aplicativo adicionado ao início automático do Windows${startMinimized ? ' (minimizado)' : ''}',
          );
        } else {
          LoggerService.error(
            'Erro ao adicionar ao início automático',
            Exception(result.stderr),
          );
        }
      } else {
        final result = await _processRunner('reg', [
          'delete',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          'BackupDatabase',
          '/f',
        ]);

        if (result.exitCode == 0) {
          LoggerService.info(
            'Aplicativo removido do início automático do Windows',
          );
        } else {
          if (result.exitCode != 1) {
            LoggerService.error(
              'Erro ao remover do início automático',
              Exception(result.stderr),
            );
          }
        }
      }
    } on Object catch (e) {
      LoggerService.error('Erro ao atualizar início automático do Windows', e);
    }
  }

  Future<void> loadSettings() async {
    await initialize();
  }

  Future<void> saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_minimizeToTrayKey, _minimizeToTray);
      await prefs.setBool(_closeToTrayKey, _closeToTray);
      await prefs.setBool(_startMinimizedKey, _startMinimized);
      await prefs.setBool(_startWithWindowsKey, _startWithWindows);
      LoggerService.info('Configurações salvas com sucesso');
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configurações', e);
    }
  }
}
