import 'dart:async';

import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';

typedef WindowsBackdropApplier = Future<void> Function({
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
    this.initializationTimeout = const Duration(seconds: 15),
    this.cancelInitialization,
    this.appearanceTimeout = const Duration(seconds: 3),
  });

  final bool Function() isWindowManagementEnabled;
  final String Function() windowManagementDisabledLabel;
  final Future<void> Function() initializeWindow;
  final WindowsBackdropApplier applyWindowsBackdrop;
  final WindowsBackdropPreferencesLoader loadWindowsBackdropPreferences;
  final bool Function() isWindowsPlatform;
  final BootstrapLog logInfo;
  final BootstrapLogWithError logWarning;
  final Duration initializationTimeout;
  final void Function()? cancelInitialization;
  final Duration appearanceTimeout;

  Future<void> start() async {
    if (!isWindowManagementEnabled()) {
      logWarning(
        'Window manager omitido (compatibilidade): '
        '${windowManagementDisabledLabel()}',
      );
      if (isWindowsPlatform()) {
        throw StateError(
          'A janela não pode ser inicializada: '
          '${windowManagementDisabledLabel()}',
        );
      }
      return;
    }

    // A failed native window is fatal. Continuing would leave an invisible
    // process holding the instance lock until manually killed.
    await initializeWindow().timeout(
      initializationTimeout,
      onTimeout: () {
        // Future.timeout alone does not stop a late native completion.
        cancelInitialization?.call();
        throw TimeoutException(
          'Window initialization timed out',
          initializationTimeout,
        );
      },
    );
    try {
      if (isWindowsPlatform()) {
        final prefs = await loadWindowsBackdropPreferences().timeout(
          appearanceTimeout,
        );
        await applyWindowsBackdrop(
          micaEnabled: prefs.micaEnabled,
          isDark: prefs.isDark,
        ).timeout(appearanceTimeout);
      }
      logInfo('Window manager pronto');
    } on Object catch (e, stackTrace) {
      logWarning(
        'Erro ao aplicar aparência da janela (mantendo janela funcional): $e',
        e,
        stackTrace,
      );
    }
  }
}
