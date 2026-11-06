import 'dart:async';

import 'package:backup_database/presentation/managers/window_manager_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
    fail = false;
    await manager.initialize(center: false);
    expect(manager.isInitialized, isTrue);
  });
}
