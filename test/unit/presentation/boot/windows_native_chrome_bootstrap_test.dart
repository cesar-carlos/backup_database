import 'dart:async';
import 'dart:io' show Platform;

import 'package:backup_database/presentation/boot/windows_native_chrome_bootstrap.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.alexmercerind/flutter_acrylic');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('theme sync cannot re-enable Mica after pending disable', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await WindowsNativeChromeBootstrap.setBackdrop(
      micaEnabled: true,
      isDark: false,
    );
    final entered = Completer<void>();
    final release = Completer<void>();
    final effects = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'SetEffect') {
        final effect = (call.arguments as Map)['effect'] as int;
        effects.add(effect);
        if (effect == WindowEffect.disabled.index) {
          entered.complete();
          await release.future;
        }
      }
      return null;
    });
    final disabling = WindowsNativeChromeBootstrap.setBackdrop(
      micaEnabled: false,
      isDark: false,
    );
    await entered.future;
    final sync = WindowsNativeChromeBootstrap.syncMicaDarkAppearanceIfActive(
      true,
    );
    release.complete();
    await Future.wait([disabling, sync]);
    expect(effects, [WindowEffect.disabled.index]);
  }, skip: !Platform.isWindows);

  test('failed enable preserves disabled state and permits retry', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await WindowsNativeChromeBootstrap.setBackdrop(
      micaEnabled: false,
      isDark: false,
    );
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'SetEffect') {
        calls++;
        throw PlatformException(code: 'effect_failed');
      }
      return null;
    });
    await WindowsNativeChromeBootstrap.setBackdrop(
      micaEnabled: true,
      isDark: false,
    );
    await WindowsNativeChromeBootstrap.syncMicaDarkAppearanceIfActive(true);
    expect(calls, 1);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'SetEffect') calls++;
      return null;
    });
    await WindowsNativeChromeBootstrap.setBackdrop(
      micaEnabled: true,
      isDark: false,
    );
    await WindowsNativeChromeBootstrap.syncMicaDarkAppearanceIfActive(true);
    expect(calls, 3);
  }, skip: !Platform.isWindows);
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

    test(
      'syncMicaDarkAppearanceIfActive completes without throw when not on Windows',
      () async {
        if (Platform.isWindows) {
          return;
        }

        await WindowsNativeChromeBootstrap.syncMicaDarkAppearanceIfActive(true);
        await WindowsNativeChromeBootstrap.syncMicaDarkAppearanceIfActive(
          false,
        );
      },
    );
  });
}
