import 'dart:io';

import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/pending_preference_operations.dart';
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
  bool _disposed = false;
  Future<void>? _initialization;
  Future<void> _operations = Future<void>.value();
  PreferenceOperation? _activeOperation;
  bool get _canFinish => _activeOperation?.isValid ?? false;
  ({bool enabled, bool minimized})? _pendingStartupRestore;
  bool get hasStartupRecoveryError => _pendingStartupRestore != null;

  Future<bool> _restoreStartupIfNeeded() async {
    final previous = _pendingStartupRestore;
    if (previous == null) return true;
    if (!_canFinish) return false;
    final restored = await _updateStartWithWindows(
      previous.enabled,
      startMinimizedOverride: previous.minimized,
    );
    if (!_canFinish) return false;
    if (restored.ok) _pendingStartupRestore = null;
    _notifyIfActive();
    return restored.ok;
  }

  Future<void> retryStartupRecovery() => _enqueue(() async {
    await _restoreStartupIfNeeded();
  });

  bool get _inactive => _disposed || _windowManager.isShuttingDown;

  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _operations.then((_) async {
      if (!_inactive) {
        await PendingPreferenceOperations.run((operation) async {
          _activeOperation = operation;
          try {
            await action();
          } finally {
            _activeOperation = null;
          }
        });
      }
    });
    _operations = operation.catchError((Object _) {});
    return operation;
  }

  void _notifyIfActive() {
    if (!_inactive && _canFinish) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool get minimizeToTray => _minimizeToTray;
  bool get closeToTray => _closeToTray;
  bool get startMinimized => _startMinimized;
  bool get startWithWindows => _startWithWindows;

  Future<void> initialize() {
    if (_inactive || _isInitialized) return Future<void>.value();
    return _initialization ??= _enqueue(_initialize)
        .whenComplete(() => _initialization = null);
  }

  Future<void> _initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      await _userPreferences.ensureTrayDefaults();
      if (_inactive || !_canFinish) return;

      final minimize = await _userPreferences.getMinimizeToTray();
      if (_inactive || !_canFinish) return;
      final close = await _userPreferences.getCloseToTray();
      if (_inactive || !_canFinish) return;
      final startMinimized = await _machineSettings.getStartMinimized();
      if (_inactive || !_canFinish) return;
      final startWithWindows = await _machineSettings.getStartWithWindows();
      if (_inactive || !_canFinish) return;
      _minimizeToTray = minimize;
      _closeToTray = close;
      _startMinimized = startMinimized;
      _startWithWindows = startWithWindows;
      if (_inactive || !_canFinish) return;

      if (Platform.isWindows) {
        final features = service_locator.getIt<FeatureAvailabilityService>();
        if (!features.isTrayEnabled) {
          _minimizeToTray = false;
          _closeToTray = false;
        }
        if (!features.isStartupAtLogonTaskEnabled) {
          _startWithWindows = false;
        }
      }

      if (_startWithWindows) {
        await _reconcileStartupPreferenceWithSystem();
      }
      if (_inactive || !_canFinish) return;

      await _windowManager.setMinimizeToTray(_minimizeToTray);
      if (_inactive || !_canFinish) return;
      await _windowManager.setCloseToTray(_closeToTray);
      if (_inactive || !_canFinish) return;
      _isInitialized = true;

      LoggerService.info(
        'Configurações aplicadas - Minimizar para bandeja: $_minimizeToTray, Fechar para bandeja: $_closeToTray',
      );

      _notifyIfActive();
      LoggerService.info('Configurações do sistema carregadas');
    } on Object catch (e) {
      LoggerService.error('Erro ao carregar configurações do sistema', e);
    }
  }

  Future<void> setMinimizeToTray(bool value) =>
      _enqueue(() => _setMinimizeToTray(value));

  Future<void> _setMinimizeToTray(bool value) async {
    if (Platform.isWindows) {
      final features = service_locator.getIt<FeatureAvailabilityService>();
      if (!features.isTrayEnabled) {
        LoggerService.warning('minimizeToTray ignorado: bandeja indisponivel');
        return;
      }
    }
    try {
      await _userPreferences.setMinimizeToTray(value);
      if (_inactive || !_canFinish) return;
      _minimizeToTray = value;
      await _windowManager.setMinimizeToTray(value);
      _notifyIfActive();
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configuração minimizeToTray', e);
    }
  }

  Future<void> setCloseToTray(bool value) =>
      _enqueue(() => _setCloseToTray(value));

  Future<void> _setCloseToTray(bool value) async {
    if (Platform.isWindows) {
      final features = service_locator.getIt<FeatureAvailabilityService>();
      if (!features.isTrayEnabled) {
        LoggerService.warning('closeToTray ignorado: bandeja indisponivel');
        return;
      }
    }
    try {
      await _userPreferences.setCloseToTray(value);
      if (_inactive || !_canFinish) return;
      _closeToTray = value;
      await _windowManager.setCloseToTray(value);
      _notifyIfActive();
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configuração closeToTray', e);
    }
  }

  Future<void> setStartMinimized(bool value) =>
      _enqueue(() => _setStartMinimized(value));

  Future<void> _setStartMinimized(bool value) async {
    if (!_isInitialized) await _initialize();
    if (_inactive || !_isInitialized) return;
    if (!await _restoreStartupIfNeeded() || !_canFinish) return;
    try {
      if (_startWithWindows) {
        final outcome = await _updateStartWithWindows(
          true,
          startMinimizedOverride: value,
        );
        if (!outcome.ok) {
          _notifyIfActive();
          return;
        }
      }

      try {
        if (!_canFinish) return;
        await _machineSettings.setStartMinimized(value);
      } on Object {
        if (_startWithWindows && _canFinish) {
          _pendingStartupRestore = (enabled: true, minimized: _startMinimized);
          await _restoreStartupIfNeeded();
        }
        rethrow;
      }
      if (_inactive || !_canFinish) return;
      _startMinimized = value;
      _notifyIfActive();
      LoggerService.debug('Iniciar minimizado alterado: $value');
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configuração startMinimized', e);
    }
  }

  Future<void> setStartWithWindows(bool value) =>
      _enqueue(() => _setStartWithWindows(value));

  Future<void> _setStartWithWindows(bool value) async {
    if (!_isInitialized) await _initialize();
    if (_inactive || !_isInitialized) return;
    if (!await _restoreStartupIfNeeded() || !_canFinish) return;
    if (Platform.isWindows) {
      final features = service_locator.getIt<FeatureAvailabilityService>();
      if (!features.isStartupAtLogonTaskEnabled) {
        LoggerService.warning(
          'startWithWindows ignorado: tarefa de logon indisponivel',
        );
        return;
      }
    }
    try {
      final outcome = await _updateStartWithWindows(
        value,
        startMinimizedOverride: _startMinimized,
      );
      if (!outcome.ok) {
        _notifyIfActive();
        return;
      }

      try {
        if (!_canFinish) return;
        await _machineSettings.setStartWithWindows(value);
      } on Object {
        if (_canFinish) {
          _pendingStartupRestore = (
            enabled: _startWithWindows,
            minimized: _startMinimized,
          );
          await _restoreStartupIfNeeded();
        }
        rethrow;
      }
      if (_inactive || !_canFinish) return;
      _startWithWindows = value;
      _notifyIfActive();
      LoggerService.debug('Iniciar com Windows alterado: $value');
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
          startMinimizedOverride ?? await _machineSettings.getStartMinimized();
      const minimizedArg = SingleInstanceConfig.minimizedArgument;
      final startupOriginArg =
          SingleInstanceConfig.windowsStartupLaunchOriginArgument;
      final appMode = _appModeProvider();
      // §audit-2026-05-28: passar --mode=client explicitamente na task
      // de logon. Sem isso, abrir o app dependia 100% de
      // {app}\.install_mode — se o arquivo sumisse, o resolver caia
      // em `server` (default) abrindo socket server numa maquina
      // de cliente. O argumento DEVE vir antes dos demais para
      // bater com o que o installer escreve.
      final modeArg = appMode == AppMode.client ? '--mode=client' : '';
      final taskArguments = enable
          ? <String>[
              if (modeArg.isNotEmpty) modeArg,
              if (startMinimized) minimizedArg,
              startupOriginArg,
            ].join(' ').trim()
          : '';
      final installScheduledTask = appMode != AppMode.server;

      if (!_canFinish) {
        return const WindowsMachineStartupOutcome(
          ok: false,
          diagnostics: 'Operation expired',
        );
      }

      final outcome = await _windowsMachineStartup.apply(
        enabled: enable,
        installScheduledTask: installScheduledTask,
        executablePath: executablePath,
        taskArguments: taskArguments,
      );
      if (!_canFinish) {
        return const WindowsMachineStartupOutcome(
          ok: false,
          diagnostics: 'Operation expired',
        );
      }

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
    if (_inactive || !_canFinish) return;
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
        'HKCU Run/BackupDatabase ainda presente; modelo atual usa só a tarefa '
        'de logon. Migração automática ocorre se início automático estiver ativo.',
      );
    }

    var migrationApplied = false;
    if (_startWithWindows &&
        installScheduledTask &&
        inspection.needsStartupLaunchProtocolMigration) {
      LoggerService.info(
        '[startup_migration] reapply_machine_logon_task '
        'reason=hkcu_run_or_stale_task_args '
        'target_arg=${SingleInstanceConfig.windowsStartupLaunchOriginArgument}',
      );
      final outcome = await _updateStartWithWindows(
        true,
        startMinimizedOverride: _startMinimized,
      );
      if (_inactive || !_canFinish) return;
      if (outcome.ok) {
        LoggerService.info('[startup_migration] completed_ok');
        migrationApplied = true;
      } else if (outcome.diagnostics.isNotEmpty) {
        LoggerService.warning(
          '[startup_migration] apply_failed diagnostics=${outcome.diagnostics}',
        );
      }
      // A failed repair is not evidence that the user disabled startup.
      // Preserve the preference so migration can be retried on the next boot.
      if (!outcome.ok) return;
    }

    if (installScheduledTask &&
        !inspection.hasScheduledTask &&
        !migrationApplied) {
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

  Future<void> saveSettings() => _enqueue(_saveSettings);

  Future<void> _saveSettings() async {
    try {
      if (!_isInitialized) await _initialize();
      if (_inactive || !_isInitialized) return;
      if (!await _restoreStartupIfNeeded() || !_canFinish) return;
      final features = Platform.isWindows
          ? service_locator.getIt<FeatureAvailabilityService>()
          : null;
      // Disabled UI values are effective fallbacks, not user preferences.
      if (features == null || features.isTrayEnabled) {
        await _userPreferences.setMinimizeToTray(_minimizeToTray);
        if (!_canFinish) return;
        await _userPreferences.setCloseToTray(_closeToTray);
      }
      if (!_canFinish) return;
      await _machineSettings.setStartMinimized(_startMinimized);
      if (!_canFinish) return;
      if (features == null || features.isStartupAtLogonTaskEnabled) {
        await _machineSettings.setStartWithWindows(_startWithWindows);
      }
      if (!_canFinish) return;
      LoggerService.info('Configurações salvas com sucesso');
    } on Object catch (e) {
      LoggerService.error('Erro ao salvar configurações', e);
    }
  }
}
