import 'package:backup_database/core/config/single_instance_config.dart';

/// Interface for single instance management service.
///
typedef RunScheduleIpcHandler = Future<int> Function(String scheduleId);

/// Why [ISingleInstanceService.checkAndLock] refused to become the owner.
enum SingleInstanceLockDenialReason {
  /// Another process already holds the machine-global mutex.
  alreadyRunning,

  /// CreateMutex failed or threw. This is not evidence of another copy.
  creationFailed,
}

/// Enforces the selected process scope: one machine-global executor, or one
/// administrative window per Windows session, with separate IPC endpoints.
abstract class ISingleInstanceService {
  /// Checks if this is the first instance and acquires the lock.
  ///
  /// Returns `true` if this is the first instance (lock acquired).
  /// Returns `false` when another instance holds the mutex or when
  /// CreateMutex fails. Read [lockDenialReason] to tell those apart.
  ///
  /// [isServiceMode] affects fallback/logging policy. A standalone UI and the
  /// service compete for the executor lock; administrative UI uses its own lock.
  ///
  /// [fallbackMode] overrides env/provider resolution when set.
  Future<bool> checkAndLock({
    bool isServiceMode = false,
    SingleInstanceLockFallbackMode? fallbackMode,
  });

  /// Starts the IPC server to receive commands from other instances.
  ///
  /// [onShowWindow] callback is invoked when another instance requests
  /// to bring the window to foreground. [onRunSchedule] executes delegated
  /// Task Scheduler launches on the process that owns the global lock.
  Future<bool> startIpcServer({
    required String role,
    Future<Object?> Function()? onShowWindow,
    RunScheduleIpcHandler? onRunSchedule,
  });

  /// Releases the mutex lock and stops the IPC server.
  Future<void> releaseLock();

  /// Why the last [checkAndLock] returned false. Null when this process
  /// holds the lock or the check has not finished.
  SingleInstanceLockDenialReason? get lockDenialReason;

  /// True while some other process still holds the instance mutex.
  /// A probe that cannot tell (API error) reports true so callers keep
  /// a bounded retry instead of treating the owner as gone.
  bool isInstanceMutexHeld();

  /// Whether this instance holds the lock (is the first instance).
  bool get isFirstInstance;

  /// Whether the IPC server is currently running.
  bool get isIpcRunning;
}
