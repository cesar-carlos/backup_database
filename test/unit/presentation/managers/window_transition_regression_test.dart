import 'dart:async';

import 'package:backup_database/core/utils/ipc_show_window_confirmation.dart';
import 'package:backup_database/presentation/managers/window_manager_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final manager = WindowManagerService();
  late bool visible;
  late bool skipTaskbar;
  late List<String> calls;
  Future<Object?> respond(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'show':
        visible = true;
      case 'hide':
        visible = false;
      case 'setSkipTaskbar':
        skipTaskbar = (call.arguments as Map)['isSkipTaskbar'] as bool;
      case 'isVisible':
        return visible;
      case 'isMinimized':
        return false;
    }
    if (call.method.startsWith('is')) return false;
    return null;
  }

  setUp(() {
    visible = false;
    skipTaskbar = true;
    calls = [];
    IpcShowWindowConfirmation.resetForTest();
    messenger.setMockMethodCallHandler(channel, respond);
  });

  test(
    'shutdown cancels active restoration and queued show requests',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setSkipTaskbar' && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        return respond(call);
      });
      final active = manager.show();
      await entered.future;
      final queued = manager.show();
      manager.beginShutdown();
      release.complete();
      await Future.wait([active, queued, manager.show()]);
      expect(calls, isNot(contains('show')));
      // A new UI lifecycle explicitly re-enables native operations.
      await manager.initialize(center: false);
    },
  );
  tearDown(() {
    manager.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('tray failure restores a window hidden after normal startup', () async {
    await manager.initialize(center: false);
    await manager.setCloseToTray(true);
    await manager.onWindowClose();
    expect(visible, isFalse);
    await manager.handleTrayUnavailable();
    expect(visible, isTrue);
    expect(skipTaskbar, isFalse);
    expect(manager.trayAvailable, isFalse);
  });

  test('queued hide is ignored after tray becomes unavailable', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'show') {
        entered.complete();
        await release.future;
      }
      return respond(call);
    });
    await manager.setCloseToTray(true);
    final showing = manager.show();
    await entered.future;
    final closing = manager.onWindowClose();
    await manager.handleTrayUnavailable();
    release.complete();
    await Future.wait([showing, closing]);
    expect(calls, isNot(contains('hide')));
    expect(visible, isTrue);
  });

  test('dispose cancels an in-flight restore before native show', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setSkipTaskbar') {
        entered.complete();
        await release.future;
      }
      return respond(call);
    });
    final show = manager.show();
    await entered.future;
    manager.dispose();
    release.complete();
    await show;
    expect(calls, isNot(contains('show')));
    expect(calls, isNot(contains('focus')));
  });

  test('concurrent maximize toggles are serialized', () async {
    var maximized = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isMaximized') return maximized;
      if (call.method == 'maximize') maximized = true;
      if (call.method == 'unmaximize') maximized = false;
      return respond(call);
    });
    await Future.wait([manager.maximize(), manager.maximize()]);
    expect(calls, ['maximize', 'unmaximize']);
    expect(maximized, isFalse);
  });

  test('minimize and maximize do not run during shutdown', () async {
    manager.beginShutdown();
    await Future.wait([manager.minimize(), manager.maximize()]);
    expect(calls, isEmpty);
    await manager.initialize(center: false);
  });

  test(
    'restore requested during hide finishes visible and on taskbar',
    () async {
      final hiding = Completer<void>();
      final finishHide = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'hide') {
          hiding.complete();
          await finishHide.future;
        }
        return respond(call);
      });
      await manager.setCloseToTray(true);
      final close = manager.onWindowClose();
      await hiding.future;
      final show = manager.show();
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty);
      finishHide.complete();
      await Future.wait([close, show]);
      expect(visible, isTrue);
      expect(skipTaskbar, isFalse);
      expect(calls.indexOf('hide'), lessThan(calls.indexOf('show')));
    },
  );

  test('close requested during restore finishes hidden', () async {
    final showing = Completer<void>();
    final finishShow = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'show') {
        showing.complete();
        await finishShow.future;
      }
      return respond(call);
    });
    await manager.setCloseToTray(true);
    final show = manager.show();
    await showing.future;
    final close = manager.onWindowClose();
    finishShow.complete();
    await Future.wait([show, close]);
    expect(visible, isFalse);
    expect(skipTaskbar, isTrue);
    expect(calls.indexOf('show'), lessThan(calls.indexOf('hide')));
  });

  test(
    'invisible native window reports failure and later requests still work',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'show') return null;
        return respond(call);
      });
      await expectLater(manager.show(), throwsStateError);
      messenger.setMockMethodCallHandler(channel, respond);
      await manager.restore();
      expect(visible, isTrue);
      expect(skipTaskbar, isFalse);
    },
  );

  test(
    'fallback retries taskbar restoration after a transient native error',
    () async {
      var failTaskbar = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setSkipTaskbar' && failTaskbar) {
          failTaskbar = false;
          throw PlatformException(code: 'temporary_error');
        }
        return respond(call);
      });
      await manager.show();
      expect(visible, isTrue);
      expect(skipTaskbar, isFalse);
    },
  );
}
