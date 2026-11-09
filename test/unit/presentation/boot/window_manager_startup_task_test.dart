import 'dart:async';

import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';
import 'package:backup_database/presentation/boot/window_manager_startup_task.dart';
import 'package:flutter_test/flutter_test.dart';

void _ignoreLog(String _) {}

void _ignoreLogWithError(
  String _, [
  Object? ignoredError,
  StackTrace? ignoredStackTrace,
]) {}

WindowManagerStartupTask _buildTask({
  required bool isEnabled,
  required List<String> events,
  bool isWindows = false,
  bool throwOnInit = false,
  Future<void> Function()? initializeWindow,
  Duration initializationTimeout = const Duration(seconds: 15),
  void Function()? cancelInitialization,
  bool throwOnBackdrop = false,
  Future<({bool micaEnabled, bool isDark})> Function()? loadPreferences,
  WindowsBackdropApplier? applyBackdrop,
  Duration appearanceTimeout = const Duration(seconds: 3),
  ({bool micaEnabled, bool isDark}) prefs = (micaEnabled: true, isDark: false),
  BootstrapLog? logInfo,
  BootstrapLogWithError? logWarning,
}) {
  return WindowManagerStartupTask(
    isWindowManagementEnabled: () => isEnabled,
    windowManagementDisabledLabel: () => 'unsupported_runtime',
    initializationTimeout: initializationTimeout,
    cancelInitialization: cancelInitialization,
    appearanceTimeout: appearanceTimeout,
    initializeWindow:
        initializeWindow ??
        () async {
          events.add('init');
          if (throwOnInit) {
            throw StateError('init boom');
          }
        },
    applyWindowsBackdrop:
        applyBackdrop ??
        ({required micaEnabled, required isDark}) async {
          events.add('backdrop:mica=$micaEnabled,dark=$isDark');
          if (throwOnBackdrop) {
            throw StateError('backdrop boom');
          }
        },
    loadWindowsBackdropPreferences:
        loadPreferences ??
        () async {
          events.add('load_prefs');
          return prefs;
        },
    isWindowsPlatform: () => isWindows,
    logInfo: logInfo ?? _ignoreLog,
    logWarning: logWarning ?? _ignoreLogWithError,
  );
}

void main() {
  test('Windows cannot continue without a usable window manager', () async {
    await expectLater(
      _buildTask(isEnabled: false, isWindows: true, events: []).start(),
      throwsStateError,
    );
  });
  test(
    'late appearance preferences do not block boot or apply later',
    () async {
      final pending = Completer<({bool micaEnabled, bool isDark})>();
      final events = <String>[];
      await _buildTask(
        isEnabled: true,
        isWindows: true,
        events: events,
        loadPreferences: () => pending.future,
        appearanceTimeout: const Duration(milliseconds: 10),
      ).start();
      pending.complete((micaEnabled: true, isDark: false));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['init']);
    },
  );
  test('unresponsive backdrop does not block boot', () async {
    final pending = Completer<void>();
    await _buildTask(
      isEnabled: true,
      isWindows: true,
      events: [],
      applyBackdrop: ({required micaEnabled, required isDark}) =>
          pending.future,
      appearanceTimeout: const Duration(milliseconds: 10),
    ).start();
    pending.complete();
  });
  group('WindowManagerStartupTask.start', () {
    test('skips initialize when window management disabled', () async {
      final events = <String>[];
      final warnings = <String>[];
      final task = _buildTask(
        isEnabled: false,
        events: events,
        logWarning: (message, [_, _]) => warnings.add(message),
      );

      await task.start();

      expect(events, isEmpty);
      expect(warnings.first, contains('Window manager omitido'));
      expect(warnings.first, contains('unsupported_runtime'));
    });

    test('only initializes window on non-Windows platforms', () async {
      final events = <String>[];
      final task = _buildTask(isEnabled: true, events: events);

      await task.start();

      expect(events, equals(['init']));
    });

    test('applies backdrop using loaded preferences on Windows', () async {
      final events = <String>[];
      final task = _buildTask(
        isEnabled: true,
        events: events,
        isWindows: true,
        prefs: (micaEnabled: true, isDark: true),
      );

      await task.start();

      expect(
        events,
        equals(['init', 'load_prefs', 'backdrop:mica=true,dark=true']),
      );
    });

    test('times out an unresponsive native window', () async {
      final pending = Completer<void>();
      final events = <String>[];
      final task = _buildTask(
        isEnabled: true,
        events: events,
        isWindows: true,
        initializeWindow: () => pending.future,
        cancelInitialization: () => events.add('cancel'),
        initializationTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(task.start(), throwsA(isA<TimeoutException>()));
      expect(events, ['cancel']);
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(events, ['cancel']);
    });

    test('backdrop failure leaves functional window available', () async {
      final warnings = <String>[];
      final task = _buildTask(
        isEnabled: true,
        events: [],
        isWindows: true,
        throwOnBackdrop: true,
        logWarning: (message, [_, _]) => warnings.add(message),
      );
      await task.start();
      expect(warnings.single, contains('aparência'));
    });

    test('propagates native window failure', () async {
      final events = <String>[];
      final warnings = <String>[];
      final task = _buildTask(
        isEnabled: true,
        events: events,
        throwOnInit: true,
        logWarning: (message, [_, _]) => warnings.add(message),
      );

      await expectLater(task.start(), throwsStateError);
      expect(events, equals(['init']));
      expect(warnings, isEmpty);
    });
  });
}
