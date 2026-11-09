import 'dart:io' show Platform;

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

class WindowsNativeChromeBootstrap {
  WindowsNativeChromeBootstrap._();

  static bool _pluginInitialized = false;
  static bool _lastMicaEnabled = false;
  static Future<void> _operations = Future<void>.value();

  static Future<void> _enqueue(Future<void> Function() action) {
    if (!Platform.isWindows) return Future<void>.value();
    final operation = _operations.then((_) => action());
    return _operations = operation.catchError((Object e, StackTrace s) {
      LoggerService.warning(
        'Windows native chrome: failed to apply backdrop',
        e,
        s,
      );
    });
  }

  static Future<void> setBackdrop({
    required bool micaEnabled,
    required bool isDark,
  }) => _enqueue(() async {
    if (!_pluginInitialized) {
      await Window.initialize();
      _pluginInitialized = true;
    }
    await Window.setEffect(
      effect: micaEnabled ? WindowEffect.mica : WindowEffect.disabled,
      dark: isDark,
    );
    _lastMicaEnabled = micaEnabled;
  });

  static Future<void> syncMicaDarkAppearanceIfActive(bool isDark) =>
      _enqueue(() async {
        if (!_pluginInitialized || !_lastMicaEnabled) {
          return;
        }
        await Window.setEffect(
          effect: WindowEffect.mica,
          dark: isDark,
        );
      });
}
