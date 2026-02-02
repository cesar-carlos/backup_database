/// Interface for single instance management service.
///
/// Ensures only one instance of the application runs at a time
/// using Windows mutexes and IPC communication.
abstract class ISingleInstanceService {
  /// Checks if this is the first instance and acquires the lock.
  ///
  /// Returns `true` if this is the first instance (lock acquired),
  /// `false` if another instance is already running.
  ///
  /// [isServiceMode] determines which mutex to use (UI or Service mode).
  Future<bool> checkAndLock({bool isServiceMode = false});

  /// Starts the IPC server to receive commands from other instances.
  ///
  /// [onShowWindow] callback is invoked when another instance requests
  /// to bring the window to foreground.
  Future<bool> startIpcServer({Function()? onShowWindow});

  /// Releases the mutex lock and stops the IPC server.
  Future<void> releaseLock();

  /// Whether this instance holds the lock (is the first instance).
  bool get isFirstInstance;

  /// Whether the IPC server is currently running.
  bool get isIpcRunning;
}
