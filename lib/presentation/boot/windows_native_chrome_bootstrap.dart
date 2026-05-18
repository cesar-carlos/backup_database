import 'dart:io' show Platform;

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

class WindowsNativeChromeBootstrap {
  WindowsNativeChromeBootstrap._();

  static bool _pluginInitialized = false;
  static bool _lastMicaEnabled = false;

  static Future<void> setBackdrop({
    required bool micaEnabled,
    required bool isDark,
  }) async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      if (!_pluginInitialized) {
        await Window.initialize();
        _pluginInitialized = true;
      }
      _lastMicaEnabled = micaEnabled;
      await Window.setEffect(
        effect: micaEnabled ? WindowEffect.mica : WindowEffect.disabled,
        dark: isDark,
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        'Windows native chrome (flutter_acrylic): failed to apply backdrop',
        e,
        s,
      );
    }
  }

  static Future<void> syncMicaDarkAppearanceIfActive(bool isDark) async {
    if (!Platform.isWindows || !_pluginInitialized || !_lastMicaEnabled) {
      return;
    }
    try {
      await Window.setEffect(
        effect: WindowEffect.mica,
        dark: isDark,
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        'Windows native chrome: failed to sync Mica dark flag',
        e,
        s,
      );
    }
  }
}
