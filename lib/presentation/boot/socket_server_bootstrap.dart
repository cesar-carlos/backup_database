import 'package:backup_database/core/config/app_mode_policy.dart';

typedef SocketServerBootstrapAction = Future<void> Function();
typedef SocketServerBootstrapLog = void Function(String message);

/// Shared socket-server startup sequence for UI bootstrap and Windows service.
abstract final class SocketServerBootstrap {
  /// Execution queue init, lock cleanup, socket listen, remote staging cleanup.
  static Future<void> start({
    required SocketServerBootstrapAction initializeExecutionQueue,
    required bool Function() isSocketServerRunning,
    required int Function() socketServerPort,
    required SocketServerBootstrapAction cleanupExpiredFileTransferLocks,
    required SocketServerBootstrapAction startSocketServer,
    required SocketServerBootstrapAction startRemoteStagingCleanup,
    SocketServerBootstrapLog? logInfo,
  }) async {
    if (!AppModePolicy.shouldStartSocketServer) {
      return;
    }

    await initializeExecutionQueue();

    if (isSocketServerRunning()) {
      logInfo?.call(
        'Socket server ja esta rodando na porta ${socketServerPort()}',
      );
      return;
    }

    await cleanupExpiredFileTransferLocks();
    await startSocketServer();
    await startRemoteStagingCleanup();
    logInfo?.call(
      'Socket server iniciado automaticamente na porta ${socketServerPort()}',
    );
  }

  /// Lock cleanup and socket listen when queue/staging already started.
  static Future<void> ensureListening({
    required bool Function() isSocketServerRunning,
    required int Function() socketServerPort,
    required SocketServerBootstrapAction cleanupExpiredFileTransferLocks,
    required SocketServerBootstrapAction startSocketServer,
    SocketServerBootstrapLog? logInfo,
  }) async {
    if (!AppModePolicy.shouldStartSocketServer) {
      return;
    }

    if (isSocketServerRunning()) {
      logInfo?.call(
        'Socket server ja esta rodando na porta ${socketServerPort()}',
      );
      return;
    }

    await cleanupExpiredFileTransferLocks();
    await startSocketServer();
    logInfo?.call(
      'Socket server iniciado no modo servico na porta ${socketServerPort()}',
    );
  }
}
