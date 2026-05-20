import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/presentation/boot/bootstrap_config.dart';
import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';

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
    if (config.appMode != AppMode.server) {
      logInfo('Modo cliente detectado - socket server nao sera iniciado');
      return;
    }

    try {
      await initializeExecutionQueue();

      if (isSocketServerRunning()) {
        logInfo(
          'Socket server ja esta rodando na porta ${socketServerPort()}',
        );
        return;
      }

      await cleanupExpiredFileTransferLocks();
      await startSocketServer();
      await startRemoteStagingCleanup();
      logInfo('Socket server iniciado automaticamente na porta 9527');
    } on Object catch (e, stackTrace) {
      logError('Erro ao iniciar socket server', e, stackTrace);
    }
  }
}
