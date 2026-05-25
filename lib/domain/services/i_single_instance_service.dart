/// Interface for single instance management service.
///
typedef RunScheduleIpcHandler = Future<int> Function(String scheduleId);

/// Ensures only one process of the application runs at a time
/// using a machine-global Windows mutex and IPC communication.
abstract class ISingleInstanceService {
  /// Checks if this is the first instance and acquires the lock.
  ///
  /// Returns `true` if this is the first instance (lock acquired),
  /// `false` if another instance is already running.
  ///
  /// [isServiceMode] only affects fallback/logging policy; UI and service
  /// compete for the same machine-global mutex.
  Future<bool> checkAndLock({bool isServiceMode = false});

  /// Starts the IPC server to receive commands from other instances.
  ///
  /// [onShowWindow] callback is invoked when another instance requests
  /// to bring the window to foreground. [onRunSchedule] executes delegated
  /// Task Scheduler launches on the process that owns the global lock.
  Future<bool> startIpcServer({
    required String role,
    Function()? onShowWindow,
    RunScheduleIpcHandler? onRunSchedule,
  });

  /// Releases the mutex lock and stops the IPC server.
  Future<void> releaseLock();

  /// Whether this instance holds the lock (is the first instance).
  bool get isFirstInstance;

  /// Whether the IPC server is currently running.
  bool get isIpcRunning;
}
