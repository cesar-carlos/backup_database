/// Temporary vetoes of application closing (for example, concurrent OAuth
/// flows). Native interception belongs exclusively to WindowManagerService.
class WindowCloseGuard {
  WindowCloseGuard._();

  static int _blocks = 0;
  static bool get isBlocked => _blocks > 0;

  static void Function() acquire() {
    _blocks++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _blocks--;
    };
  }
}
