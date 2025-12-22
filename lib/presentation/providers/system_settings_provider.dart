import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../managers/window_manager_service.dart';
import '../../core/utils/logger_service.dart';

class SystemSettingsProvider extends ChangeNotifier {
  final WindowManagerService _windowManager;

  static const String _minimizeToTrayKey = 'minimize_to_tray';
  static const String _closeToTrayKey = 'close_to_tray';
  static const String _startMinimizedKey = 'start_minimized';
  static const String _startWithWindowsKey = 'start_with_windows';

  bool _minimizeToTray = true;
  bool _closeToTray = true;
  bool _startMinimized = true;
  bool _startWithWindows = true;
  bool _isInitialized = false;

  SystemSettingsProvider({
    WindowManagerService? windowManager,
  })  : _windowManager = windowManager ?? WindowManagerService();

  bool get minimizeToTray => _minimizeToTray;
  bool get closeToTray => _closeToTray;
  bool get startMinimized => _startMinimized;
  bool get startWithWindows => _startWithWindows;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Verificar se é a primeira inicialização (nenhum valor salvo)
      final isFirstRun = !prefs.containsKey(_minimizeToTrayKey) &&
          !prefs.containsKey(_closeToTrayKey) &&
          !prefs.containsKey(_startMinimizedKey) &&
          !prefs.containsKey(_startWithWindowsKey);
      
      _minimizeToTray = prefs.getBool(_minimizeToTrayKey) ?? true;
      _closeToTray = prefs.getBool(_closeToTrayKey) ?? true;
      _startMinimized = prefs.getBool(_startMinimizedKey) ?? true;
      _startWithWindows = prefs.getBool(_startWithWindowsKey) ?? true;
      
      // Se for a primeira inicialização, salvar os valores padrão
      if (isFirstRun) {
        await prefs.setBool(_minimizeToTrayKey, _minimizeToTray);
        await prefs.setBool(_closeToTrayKey, _closeToTray);
        await prefs.setBool(_startMinimizedKey, _startMinimized);
        await prefs.setBool(_startWithWindowsKey, _startWithWindows);
        LoggerService.info('Primeira inicialização - valores padrão salvos');
        
        // Se "Iniciar com o Windows" estiver ativado, configurar no registro
        if (_startWithWindows) {
          await _updateStartWithWindows(true);
        }
      }
      
      _isInitialized = true;

      // Aplicar configurações carregadas
      _windowManager.setMinimizeToTray(_minimizeToTray);
      _windowManager.setCloseToTray(_closeToTray);
      
      LoggerService.info(
        'Configurações aplicadas - Minimizar para bandeja: $_minimizeToTray, Fechar para bandeja: $_closeToTray',
      );

      notifyListeners();
      LoggerService.info('Configurações do sistema carregadas');
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
      
      // Se "Iniciar com o Windows" estiver ativado, atualizar o registro
      if (_startWithWindows) {
        await _updateStartWithWindows(true);
      }
    } catch (e) {
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
    } catch (e) {
      LoggerService.error('Erro ao salvar configuração startWithWindows', e);
    }
  }

  Future<void> _updateStartWithWindows(bool enable) async {
    try {
      final executablePath = Platform.resolvedExecutable;
      
      if (enable) {
        // Verificar se deve iniciar minimizado
        final prefs = await SharedPreferences.getInstance();
        final startMinimized = prefs.getBool(_startMinimizedKey) ?? true;
        
        // Construir comando com argumento --minimized se necessário
        final command = startMinimized 
            ? '"$executablePath" --minimized'
            : '"$executablePath"';
        
        // Adicionar ao registro do Windows
        final result = await Process.run(
          'reg',
          [
            'add',
            'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
            '/v',
            'BackupDatabase',
            '/t',
            'REG_SZ',
            '/d',
            command,
            '/f',
          ],
        );
        
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
        // Remover do registro do Windows
        final result = await Process.run(
          'reg',
          [
            'delete',
            'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
            '/v',
            'BackupDatabase',
            '/f',
          ],
        );
        
        if (result.exitCode == 0) {
          LoggerService.info('Aplicativo removido do início automático do Windows');
        } else {
          // Exit code 1 significa que a chave não existe, o que é OK
          if (result.exitCode != 1) {
            LoggerService.error(
              'Erro ao remover do início automático',
              Exception(result.stderr),
            );
          }
        }
      }
    } catch (e) {
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
    } catch (e) {
      LoggerService.error('Erro ao salvar configurações', e);
    }
  }
}

