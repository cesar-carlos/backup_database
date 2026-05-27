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
  bool throwOnBackdrop = false,
  ({bool micaEnabled, bool isDark}) prefs = (micaEnabled: true, isDark: false),
  BootstrapLog? logInfo,
  BootstrapLogWithError? logWarning,
}) {
  return WindowManagerStartupTask(
    isWindowManagementEnabled: () => isEnabled,
    windowManagementDisabledLabel: () => 'unsupported_runtime',
    initializeWindow: () async {
      events.add('init');
      if (throwOnInit) {
        throw StateError('init boom');
      }
    },
    applyWindowsBackdrop: ({required micaEnabled, required isDark}) async {
      events.add('backdrop:mica=$micaEnabled,dark=$isDark');
      if (throwOnBackdrop) {
        throw StateError('backdrop boom');
      }
    },
    loadWindowsBackdropPreferences: () async {
      events.add('load_prefs');
      return prefs;
    },
    isWindowsPlatform: () => isWindows,
    logInfo: logInfo ?? _ignoreLog,
    logWarning: logWarning ?? _ignoreLogWithError,
  );
}

void main() {
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

    test('logs warning and swallows init failure', () async {
      final events = <String>[];
      final warnings = <String>[];
      final task = _buildTask(
        isEnabled: true,
        events: events,
        throwOnInit: true,
        logWarning: (message, [_, _]) => warnings.add(message),
      );

      await task.start();

      expect(events, equals(['init']));
      expect(warnings.first, contains('Erro ao inicializar window manager'));
    });
  });
}
