import 'package:backup_database/domain/services/i_single_instance_service.dart';

/// Interface for inter-process communication between application instances.
abstract class IIpcService {
  /// Starts the IPC server to listen for commands from other instances.
  Future<bool> startServer({
    required String role,
    Function()? onShowWindow,
    RunScheduleIpcHandler? onRunSchedule,
  });

  /// Stops the IPC server.
  Future<void> stop();

  /// Whether the IPC server is currently running.
  bool get isRunning;
}
