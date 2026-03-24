import 'dart:io';

import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/domain/services/i_windows_machine_startup_service.dart';
import 'package:backup_database/presentation/managers/window_manager_service.dart';
import 'package:flutter/foundation.dart';

class SystemSettingsProvider extends ChangeNotifier {
  SystemSettingsProvider({
    required IMachineSettingsRepository machineSettingsRepository,
    required IUserPreferencesRepository userPreferencesRepository,
    required IWindowsMachineStartupService windowsMachineStartupService,
    WindowManagerService? windowManager,
    String Function()? executablePathProvider,
    AppMode Function()? appModeProvider,
  }) : _machineSettings = machineSettingsRepository,
       _userPreferences = userPreferencesRepository,
       _windowsMachineStartup = windowsMachineStartupService,
       _windowManager = windowManager ?? WindowManagerService(),
       _executablePathProvider =
           executablePathProvider ?? (() => Platform.resolvedExecutable),
       _appModeProvider = appModeProvider ?? (() => currentAppMode);

  final IMachineSettingsRepository _machineSettings;
  final IUserPreferencesRepository _userPreferences;
  final IWindowsMachineStartupService _windowsMachineStartup;
  final WindowManagerService _windowManager;
  final String Function() _executablePathProvider;
  final AppMode Function() _appModeProvider;

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
    if (_isInitialized) {
      return;
    }

    try {
      await _userPreferences.ensureTrayDefaults();

      _minimizeToTray = await _userPreferences.getMinimizeToTray();
      _closeToTray = await _userPreferences.getCloseToTray();
      _startMinimized = await _machineSettings.getStartMinimized();
      _startWithWindows = await _machineSettings.getStartWithWindows();

      if (_startWithWindows) {
        await _reconcileStartupPreferenceWithSystem();
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
      await _userPreferences.setMinimizeToTray(value);
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
      await _userPreferences.setCloseToTray(value);
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configuração closeToTray', e);
    }
  }

  Future<void> setStartMinimized(bool value) async {
    try {
      if (_startWithWindows) {
        final outcome = await _updateStartWithWindows(
          true,
          startMinimizedOverride: value,
        );
        if (!outcome.ok) {
          notifyListeners();
          return;
        }
      }

      _startMinimized = value;
      notifyListeners();
      LoggerService.debug('Iniciar minimizado alterado: $value');
      await _machineSettings.setStartMinimized(value);
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configuração startMinimized', e);
    }
  }

  Future<void> setStartWithWindows(bool value) async {
    try {
      final outcome = await _updateStartWithWindows(
        value,
        startMinimizedOverride: _startMinimized,
      );
      if (!outcome.ok) {
        notifyListeners();
        return;
      }

      _startWithWindows = value;
      notifyListeners();
      LoggerService.debug('Iniciar com Windows alterado: $value');
      await _machineSettings.setStartWithWindows(value);
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configuração startWithWindows', e);
    }
  }

  Future<WindowsMachineStartupOutcome> _updateStartWithWindows(
    bool enable, {
    bool? startMinimizedOverride,
  }) async {
    try {
      final executablePath = _executablePathProvider();
      final startMinimized =
          startMinimizedOverride ??
          await _machineSettings.getStartMinimized();
      const startupArg = SingleInstanceConfig.startupLaunchArgument;
      const minimizedArg = SingleInstanceConfig.minimizedArgument;
      final taskArguments = enable
          ? (startMinimized ? '$minimizedArg $startupArg' : startupArg).trim()
          : '';
      final installScheduledTask = _appModeProvider() != AppMode.server;

      final outcome = await _windowsMachineStartup.apply(
        enabled: enable,
        installScheduledTask: installScheduledTask,
        executablePath: executablePath,
        taskArguments: taskArguments,
      );

      if (outcome.ok) {
        if (enable) {
          if (installScheduledTask) {
            LoggerService.info(
              'Início automático (máquina) configurado'
              '${startMinimized ? ' (minimizado)' : ''}',
            );
          }
        } else {
          LoggerService.info(
            'Início automático removido (Run legado e tarefa de logon)',
          );
        }
      } else if (outcome.diagnostics.isNotEmpty) {
        LoggerService.error(
          'Erro ao atualizar início automático',
          Exception(outcome.diagnostics),
        );
      }
      return outcome;
    } on Object catch (e) {
      LoggerService.error('Erro ao atualizar início automático do Windows', e);
      return WindowsMachineStartupOutcome(ok: false, diagnostics: '$e');
    }
  }

  Future<void> _reconcileStartupPreferenceWithSystem() async {
    final installScheduledTask = _appModeProvider() != AppMode.server;
    final inspection = await _windowsMachineStartup.inspect();
    if (!inspection.ok) {
      if (inspection.diagnostics.isNotEmpty) {
        LoggerService.warning(
          'Não foi possível inspecionar o estado atual do início automático: '
          '${inspection.diagnostics}',
        );
      }
      return;
    }

    if (inspection.hasLegacyRunEntry) {
      LoggerService.warning(
        'Entrada legada HKCU Run/BackupDatabase ainda existe no sistema',
      );
    }

    if (installScheduledTask && !inspection.hasScheduledTask) {
      LoggerService.warning(
        'Preferência de início automático estava ativa, mas a tarefa '
        'agendada não existe mais. A opção será desativada.',
      );
      _startWithWindows = false;
      await _machineSettings.setStartWithWindows(false);
      return;
    }

    if (!installScheduledTask && inspection.hasScheduledTask) {
      LoggerService.warning(
        'Modo servidor detectou tarefa agendada de logon remanescente; '
        'o autostart suportado é o Windows Service.',
      );
    }
  }

  Future<void> loadSettings() async {
    await initialize();
  }

  Future<void> saveSettings() async {
    try {
      await _userPreferences.setMinimizeToTray(_minimizeToTray);
      await _userPreferences.setCloseToTray(_closeToTray);
      await _machineSettings.setStartMinimized(_startMinimized);
      await _machineSettings.setStartWithWindows(_startWithWindows);
      LoggerService.info('Configurações salvas com sucesso');
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configurações', e);
    }
  }
}
