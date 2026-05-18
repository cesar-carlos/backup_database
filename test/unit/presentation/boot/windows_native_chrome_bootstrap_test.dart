import 'dart:io' show Platform;

import 'package:backup_database/presentation/boot/windows_native_chrome_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowsNativeChromeBootstrap', () {
    test('setBackdrop completes without throw when not on Windows', () async {
      if (Platform.isWindows) {
        return;
      }

      await WindowsNativeChromeBootstrap.setBackdrop(
        micaEnabled: true,
        isDark: false,
      );
      await WindowsNativeChromeBootstrap.setBackdrop(
        micaEnabled: false,
        isDark: true,
      );
    });

    test('syncMicaDarkAppearanceIfActive completes without throw when not on Windows', () async {
      if (Platform.isWindows) {
        return;
      }

      await WindowsNativeChromeBootstrap.syncMicaDarkAppearanceIfActive(true);
      await WindowsNativeChromeBootstrap.syncMicaDarkAppearanceIfActive(false);
    });
  });
}
