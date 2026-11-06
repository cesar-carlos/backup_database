import 'dart:async';

import 'package:backup_database/presentation/managers/tray_manager_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('mouse click and menu opening each dispatch one restore', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('tray_manager');
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final tray = TrayManagerService();
    final actions = <TrayMenuAction>[];
    try {
      await tray.initialize(onMenuAction: actions.add);
      tray.onTrayIconMouseDown();
      tray.onTrayIconMouseUp();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(actions, [TrayMenuAction.show]);
      tray.onTrayMenuItemClick(MenuItem(key: 'show', label: 'Abrir'));
      expect(actions, [TrayMenuAction.show, TrayMenuAction.show]);
      tray.onTrayMenuItemClick(MenuItem(key: 'exit', label: 'Sair'));
      expect(actions.last, TrayMenuAction.exit);
    } finally {
      await tray.dispose();
      await Future<void>.delayed(Duration.zero);
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  for (final failure in ['setToolTip', 'setContextMenu']) {
    test(
      'partial $failure failure removes icon and ignores stale events',
      () async {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channel = MethodChannel('tray_manager');
        final calls = <String>[];
        final actions = <TrayMenuAction>[];
        var shouldFail = true;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == failure && shouldFail) {
            throw PlatformException(code: 'failed');
          }
          return null;
        });
        final tray = TrayManagerService();
        try {
          await expectLater(
            tray.initialize(onMenuAction: actions.add),
            throwsA(isA<PlatformException>()),
          );
          expect(calls.last, 'destroy');
          tray.onTrayIconMouseUp();
          tray.onTrayMenuItemClick(MenuItem(key: 'exit', label: 'Sair'));
          expect(actions, isEmpty);
          shouldFail = false;
          await tray.initialize(onMenuAction: actions.add);
          tray.onTrayIconMouseUp();
          expect(actions, [TrayMenuAction.show]);
        } finally {
          await tray.dispose();
          messenger.setMockMethodCallHandler(channel, null);
        }
      },
    );
  }

  test('context menu finishes before the tray icon is destroyed', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('tray_manager');
    final menuEntered = Completer<void>();
    final finishMenu = Completer<void>();
    final calls = <String>[];
    var opening = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (opening && call.method == 'setContextMenu') {
        menuEntered.complete();
        await finishMenu.future;
      }
      calls.add(call.method);
      return null;
    });
    final tray = TrayManagerService();
    try {
      await tray.initialize();
      calls.clear();
      opening = true;
      tray.onTrayIconRightMouseDown();
      await menuEntered.future;
      final disposing = tray.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty);
      finishMenu.complete();
      await disposing;
      expect(
        calls,
        containsAllInOrder(['setContextMenu', 'popUpContextMenu', 'destroy']),
      );
    } finally {
      if (!finishMenu.isCompleted) finishMenu.complete();
      await tray.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test('reinitialization waits until the previous icon is destroyed', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('tray_manager');
    final destroyEntered = Completer<void>();
    final finishDestroy = Completer<void>();
    var icons = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setIcon') icons++;
      if (call.method == 'destroy' && !destroyEntered.isCompleted) {
        destroyEntered.complete();
        await finishDestroy.future;
      }
      return null;
    });
    final tray = TrayManagerService();
    try {
      await Future.wait([tray.initialize(), tray.initialize()]);
      expect(icons, 1);
      final disposing = tray.dispose();
      await destroyEntered.future;
      final restarting = tray.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(icons, 1);
      finishDestroy.complete();
      await Future.wait([disposing, restarting]);
      expect(icons, 2);
    } finally {
      if (!finishDestroy.isCompleted) finishDestroy.complete();
      await tray.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
