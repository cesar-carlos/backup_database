import 'package:backup_database/presentation/boot/tray_manager_startup_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrayManagerStartupTask.start', () {
    for (final enabled in [false, true]) {
      test(
        'restores window when tray ${enabled ? 'fails' : 'is disabled'}',
        () async {
          var restored = false;
          final task = TrayManagerStartupTask(
            isTrayEnabled: () => enabled,
            trayDisabledLabel: () => 'disabled',
            initializeTray: () async => throw StateError('icon failed'),
            logWarning: (_, [_, _]) {},
            onUnavailable: () async {
              restored = true;
            },
          );
          await task.start();
          expect(restored, isTrue);
        },
      );
    }
    test('skips initialization when tray disabled', () async {
      var initCalled = false;
      final warnings = <String>[];
      final task = TrayManagerStartupTask(
        isTrayEnabled: () => false,
        trayDisabledLabel: () => 'unsupported_runtime',
        initializeTray: () async {
          initCalled = true;
        },
        logWarning: (message, [_, _]) => warnings.add(message),
      );

      await task.start();

      expect(initCalled, isFalse);
      expect(warnings.first, contains('Tray icon omitido'));
      expect(warnings.first, contains('unsupported_runtime'));
    });

    test('initializes tray when enabled', () async {
      var initCalled = false;
      final task = TrayManagerStartupTask(
        isTrayEnabled: () => true,
        trayDisabledLabel: () => 'n/a',
        initializeTray: () async {
          initCalled = true;
        },
        logWarning: (_, [_, _]) {},
        onUnavailable: () async => fail('must preserve minimized startup'),
      );

      await task.start();

      expect(initCalled, isTrue);
    });

    test('logs warning and swallows initialization failure', () async {
      final warnings = <String>[];
      final task = TrayManagerStartupTask(
        isTrayEnabled: () => true,
        trayDisabledLabel: () => 'n/a',
        initializeTray: () async => throw StateError('tray boom'),
        logWarning: (message, [_, _]) => warnings.add(message),
      );

      await task.start();

      expect(warnings.first, contains('Erro ao inicializar tray manager'));
    });
  });
}
