import 'dart:async';

import 'package:backup_database/presentation/managers/window_manager_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final manager = WindowManagerService();

  tearDown(() {
    manager.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'minimize emitted by native show does not hide restored window',
    () async {
      var visible = false;
      var emitMinimize = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'show') {
          visible = true;
          if (emitMinimize) manager.onWindowMinimize();
        }
        if (call.method == 'hide') visible = false;
        if (call.method == 'isVisible') return visible;
        if (call.method.startsWith('is')) return false;
        return null;
      });
      await manager.initialize(center: false);
      await manager.setMinimizeToTray(true);
      emitMinimize = true;
      await manager.show();
      await manager.setTitle('Queue barrier');
      expect(visible, isTrue);
      manager.onWindowMinimize();
      await manager.setTitle('Queue barrier');
      expect(visible, isFalse, reason: 'Real minimize must still hide to tray');
    },
  );

  test('concurrent initialization registers exactly one listener', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var initialized = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'ensureInitialized') {
        initialized++;
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }
      if (call.method.startsWith('is')) return false;
      return null;
    });
    final first = manager.initialize(center: false);
    await entered.future;
    final second = manager.initialize(center: false);
    release.complete();
    await Future.wait([first, second]);
    expect(initialized, 1);
    expect(
      windowManager.listeners.where((item) => item == manager),
      hasLength(1),
    );
  });

  for (final shutdown in [false, true]) {
    test('boot stops after ${shutdown ? 'shutdown' : 'dispose'}', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'ensureInitialized') {
          entered.complete();
          await release.future;
        }
        return null;
      });
      final boot = manager.initialize(center: false);
      final assertion = expectLater(boot, throwsStateError);
      await entered.future;
      if (shutdown) {
        manager.beginShutdown();
      } else {
        manager.dispose();
      }
      release.complete();
      await assertion;
      expect(calls, ['ensureInitialized']);
      expect(manager.isInitialized, isFalse);
      expect(windowManager.listeners, isNot(contains(manager)));
    });
  }

  for (final startMinimized in [false, true]) {
    test(
      'preserves native chrome with startMinimized=$startMinimized',
      () async {
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method.startsWith('is')) return false;
          return null;
        });

        await manager.initialize(center: false, startMinimized: startMinimized);

        final caption = calls.singleWhere(
          (call) => call.method == 'setTitleBarStyle',
        );
        final arguments = caption.arguments as Map<Object?, Object?>;
        expect(arguments['titleBarStyle'], 'normal');
        expect(arguments['windowButtonVisibility'], isTrue);
        expect(
          calls.any((call) => call.method == 'setBackgroundColor'),
          isFalse,
        );
        final presentation = calls.indexWhere(
          (call) => call.method == (startMinimized ? 'hide' : 'show'),
        );
        expect(calls.indexOf(caption), lessThan(presentation));
        expect(
          calls.indexWhere((call) => call.method == 'setPreventClose'),
          lessThan(
            calls.indexWhere((call) => call.method == 'waitUntilReadyToShow'),
          ),
        );
        expect(manager.isInitialized, isTrue);
      },
    );
  }

  test('initialization awaits native show before reporting ready', () async {
    final showEntered = Completer<void>();
    final showFinished = Completer<void>();
    var focused = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'show') {
        showEntered.complete();
        await showFinished.future;
      }
      if (call.method == 'focus') focused = true;
      if (call.method.startsWith('is')) return false;
      return null;
    });
    var completed = false;
    final boot = manager
        .initialize(center: false)
        .then((_) => completed = true);
    await showEntered.future;
    await Future<void>.delayed(Duration.zero);
    expect(manager.isInitialized, isFalse);
    expect(completed, isFalse);
    expect(focused, isFalse);
    showFinished.complete();
    await boot;
    expect(manager.isInitialized, isTrue);
    expect(focused, isTrue);
  });

  test(
    'restore requested during hidden startup runs after boot hide',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final calls = <String>[];
      var visible = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'ensureInitialized') {
          entered.complete();
          await release.future;
        }
        if (call.method == 'show') visible = true;
        if (call.method == 'hide') visible = false;
        if (call.method == 'isVisible') return visible;
        if (call.method.startsWith('is')) return false;
        return null;
      });
      final boot = manager.initialize(center: false, startMinimized: true);
      await entered.future;
      final show = manager.show();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['ensureInitialized']);
      release.complete();
      await Future.wait([boot, show]);
      expect(visible, isTrue);
      expect(calls.indexOf('hide'), lessThan(calls.indexOf('show')));
    },
  );

  test('native show failure propagates and allows a later retry', () async {
    var fail = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'show' && fail) {
        throw PlatformException(code: 'show_failed');
      }
      if (call.method.startsWith('is')) return false;
      return null;
    });
    await expectLater(
      manager.initialize(center: false),
      throwsA(isA<PlatformException>()),
    );
    expect(manager.isInitialized, isFalse);
    expect(windowManager.listeners, isNot(contains(manager)));
    fail = false;
    await manager.initialize(center: false);
    expect(manager.isInitialized, isTrue);
    expect(
      windowManager.listeners.where((item) => item == manager),
      hasLength(1),
    );
  });
}
