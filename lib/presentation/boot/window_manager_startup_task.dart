import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';

typedef WindowsBackdropApplier =
    Future<void> Function({
      required bool micaEnabled,
      required bool isDark,
    });

typedef WindowsBackdropPreferencesLoader =
    Future<({bool micaEnabled, bool isDark})> Function();

class WindowManagerStartupTask {
  const WindowManagerStartupTask({
    required this.isWindowManagementEnabled,
    required this.windowManagementDisabledLabel,
    required this.initializeWindow,
    required this.applyWindowsBackdrop,
    required this.loadWindowsBackdropPreferences,
    required this.isWindowsPlatform,
    required this.logInfo,
    required this.logWarning,
  });

  final bool Function() isWindowManagementEnabled;
  final String Function() windowManagementDisabledLabel;
  final Future<void> Function() initializeWindow;
  final WindowsBackdropApplier applyWindowsBackdrop;
  final WindowsBackdropPreferencesLoader loadWindowsBackdropPreferences;
  final bool Function() isWindowsPlatform;
  final BootstrapLog logInfo;
  final BootstrapLogWithError logWarning;

  Future<void> start() async {
    if (!isWindowManagementEnabled()) {
      logWarning(
        'Window manager omitido (compatibilidade): '
        '${windowManagementDisabledLabel()}',
      );
      return;
    }

    try {
      await initializeWindow();
      if (isWindowsPlatform()) {
        final prefs = await loadWindowsBackdropPreferences();
        await applyWindowsBackdrop(
          micaEnabled: prefs.micaEnabled,
          isDark: prefs.isDark,
        );
      }
      logInfo('Window manager pronto');
    } on Object catch (e, stackTrace) {
      logWarning(
        'Erro ao inicializar window manager (continuando sem UI): $e',
        e,
        stackTrace,
      );
    }
  }
}
