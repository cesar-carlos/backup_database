/// Records that a window became visible during the current SHOW_WINDOW
/// attempt. The IPC handler only replies OK when this mark is set, because
/// the show callback can return before any window exists.
class IpcShowWindowConfirmation {
  IpcShowWindowConfirmation._();

  static int _epoch = 0;
  static int _shownEpoch = -1;

  static int beginAttempt() => ++_epoch;

  static void markShown() {
    _shownEpoch = _epoch;
  }

  static bool wasShown(int epoch) => _shownEpoch == epoch;

  static void resetForTest() {
    _epoch = 0;
    _shownEpoch = -1;
  }
}
