import 'dart:async';

/// Records that a window became visible during the current SHOW_WINDOW
/// attempt. The IPC handler only replies OK when this mark is set, because
/// the show callback can return before any window exists.
class IpcShowWindowConfirmation {
  IpcShowWindowConfirmation._();

  static final Object _attemptKey = Object();

  static Future<bool> runAttempt(Future<Object?> Function() callback) async {
    final attempt = _ShowAttempt();
    return runZoned(() async {
      final outcome = await callback();
      return outcome != false && (outcome == true || attempt.shown);
    }, zoneValues: {_attemptKey: attempt});
  }

  static void markShown() {
    (Zone.current[_attemptKey] as _ShowAttempt?)?.shown = true;
  }

  static void resetForTest() {}
}

class _ShowAttempt {
  bool shown = false;
}
