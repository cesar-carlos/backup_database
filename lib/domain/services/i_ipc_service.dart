/// Interface for inter-process communication between application instances.
abstract class IIpcService {
  /// Starts the IPC server to listen for commands from other instances.
  Future<bool> startServer({Function()? onShowWindow});

  /// Stops the IPC server.
  Future<void> stop();

  /// Whether the IPC server is currently running.
  bool get isRunning;
}

/// Static operations for IPC communication (client-side).
abstract class IpcClient {
  /// Sends a SHOW_WINDOW command to an existing instance.
  static Future<bool> sendShowWindow() =>
      throw UnimplementedError('Use IpcService.sendShowWindow()');

  /// Checks if an IPC server is already running.
  static Future<bool> checkServerRunning() =>
      throw UnimplementedError('Use IpcService.checkServerRunning()');

  /// Gets the username of the user running the existing instance.
  static Future<String?> getExistingInstanceUser() =>
      throw UnimplementedError('Use IpcService.getExistingInstanceUser()');
}
