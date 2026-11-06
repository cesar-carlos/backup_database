import 'dart:async';

import 'package:backup_database/core/utils/window_close_guard.dart';
import 'package:backup_database/presentation/managers/window_manager_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final manager = WindowManagerService();
  late List<MethodCall> calls;
  late int exits;
  setUp(() {
    calls = [];
    exits = 0;
    manager.setCallbacks(onClose: () => exits++);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method.startsWith('is')) return false;
      return null;
    });
  });
  tearDown(() {
    manager.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final close in [false, true]) {
    for (final minimize in [false, true]) {
      test('X with closeToTray=$close minimizeToTray=$minimize', () async {
        manager.prepareTrayCloseBehavior(
          minimizeToTray: minimize,
          closeToTray: close,
        );
        await manager.initialize(center: false);
        final prevent = calls.indexWhere((c) => c.method == 'setPreventClose');
        final show = calls.indexWhere((c) => c.method == 'show');
        expect(prevent, lessThan(show));
        expect(calls[prevent].arguments, {'isPreventClose': true});
        calls.clear();
        await manager.onWindowClose();
        expect(exits, close || minimize ? 0 : 1);
        expect(calls.any((c) => c.method == 'hide'), close || minimize);
        expect(calls.where((c) => c.method == 'setPreventClose'), isEmpty);
      });
    }
  }

  test('protection failure aborts before showing the native window', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'setPreventClose') {
        throw PlatformException(code: 'failed');
      }
      if (call.method.startsWith('is')) return false;
      return null;
    });
    await expectLater(
      manager.initialize(center: false),
      throwsA(isA<PlatformException>()),
    );
    expect(calls.any((c) => c.method == 'show'), isFalse);
    expect(manager.isInitialized, isFalse);
  });

  test(
    'changing preferences never disables native close interception',
    () async {
      await manager.initialize(center: false);
      calls.clear();
      await manager.setCloseToTray(true);
      await manager.setMinimizeToTray(false);
      await manager.onWindowClose();
      expect(exits, 0);
      expect(calls.any((c) => c.method == 'hide'), isTrue);
      expect(calls.any((c) => c.method == 'setPreventClose'), isFalse);
    },
  );

  test(
    'failed tray stays unavailable after preferences are reapplied',
    () async {
    manager.trayAvailable = false;
      await manager.setMinimizeToTray(true);
      await manager.setCloseToTray(true);
      manager.onWindowMinimize();
      await manager.onWindowClose();
      expect(exits, 1);
      expect(calls.any((c) => c.method == 'hide'), isFalse);
    },
  );

  test(
    'overlapping OAuth guards block X until the last flow completes',
    () async {
      final first = WindowCloseGuard.acquire();
      final second = WindowCloseGuard.acquire();
      try {
        await manager.onWindowClose();
        first();
        first(); // release is idempotent
        await manager.setCloseToTray(true);
        await manager.onWindowClose();
        expect(exits, 0);
        expect(calls, isEmpty);
        second();
        await manager.onWindowClose();
        expect(calls.any((c) => c.method == 'hide'), isTrue);
      } finally {
        first();
        second();
      }
    },
  );

  test('repeated X waits for one asynchronous cleanup', () async {
    final cleanup = Completer<void>();
    manager.setCallbacks(
      onClose: () async {
        exits++;
        await cleanup.future;
      },
    );
    var completed = false;
    final closing = manager.onWindowClose().then((_) => completed = true);
    await manager.onWindowClose();
    expect(exits, 1);
    expect(completed, isFalse);
    cleanup.complete();
    await closing;
    expect(completed, isTrue);
  });

  test('failed hide never invokes exit', () async {
    await manager.setCloseToTray(true);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'hide') throw PlatformException(code: 'hide_failed');
      return null;
    });
    await manager.onWindowClose();
    expect(exits, 0);
  });

  test('minimize to tray hides and removes the taskbar entry', () async {
    await manager.setMinimizeToTray(true);
    manager.onWindowMinimize();
    await Future<void>.delayed(Duration.zero);
    expect(
      calls.map((c) => c.method),
      containsAllInOrder(['hide', 'setSkipTaskbar']),
    );
    expect(exits, 0);
  });
}
