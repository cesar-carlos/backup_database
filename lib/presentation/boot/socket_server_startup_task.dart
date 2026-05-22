import 'package:backup_database/presentation/boot/bootstrap_config.dart';
import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';
import 'package:backup_database/presentation/boot/socket_server_bootstrap.dart';

class SocketServerStartupTask {
  const SocketServerStartupTask({
    required this.initializeExecutionQueue,
    required this.isSocketServerRunning,
    required this.socketServerPort,
    required this.cleanupExpiredFileTransferLocks,
    required this.startSocketServer,
    required this.startRemoteStagingCleanup,
    required this.logInfo,
    required this.logError,
  });

  final Future<void> Function() initializeExecutionQueue;
  final bool Function() isSocketServerRunning;
  final int Function() socketServerPort;
  final Future<void> Function() cleanupExpiredFileTransferLocks;
  final Future<void> Function() startSocketServer;
  final Future<void> Function() startRemoteStagingCleanup;
  final BootstrapLog logInfo;
  final BootstrapLogWithError logError;

  Future<void> start(BootstrapConfig config) async {
    try {
      await SocketServerBootstrap.start(
        initializeExecutionQueue: initializeExecutionQueue,
        isSocketServerRunning: isSocketServerRunning,
        socketServerPort: socketServerPort,
        cleanupExpiredFileTransferLocks: cleanupExpiredFileTransferLocks,
        startSocketServer: startSocketServer,
        startRemoteStagingCleanup: startRemoteStagingCleanup,
        logInfo: logInfo,
      );
    } on Object catch (e, stackTrace) {
      logError('Erro ao iniciar socket server', e, stackTrace);
    }
  }
}
