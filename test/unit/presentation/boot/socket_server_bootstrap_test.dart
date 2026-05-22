import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/presentation/boot/socket_server_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppMode? previousMode;

  setUp(() {
    previousMode = currentAppMode;
  });

  tearDown(() {
    if (previousMode != null) {
      setAppMode(previousMode!);
    }
  });

  group('SocketServerBootstrap.start', () {
    test('should skip all actions when not in server mode', () async {
      setAppMode(AppMode.client);

      var initializeCalls = 0;
      var cleanupCalls = 0;
      var startCalls = 0;
      var stagingCalls = 0;

      await SocketServerBootstrap.start(
        initializeExecutionQueue: () async => initializeCalls++,
        isSocketServerRunning: () => false,
        socketServerPort: () => 9000,
        cleanupExpiredFileTransferLocks: () async => cleanupCalls++,
        startSocketServer: () async => startCalls++,
        startRemoteStagingCleanup: () async => stagingCalls++,
      );

      expect(initializeCalls, 0);
      expect(cleanupCalls, 0);
      expect(startCalls, 0);
      expect(stagingCalls, 0);
    });

    test('should run startup sequence when in server mode', () async {
      setAppMode(AppMode.server);

      final callOrder = <String>[];

      await SocketServerBootstrap.start(
        initializeExecutionQueue: () async => callOrder.add('init'),
        isSocketServerRunning: () => false,
        socketServerPort: () => 9000,
        cleanupExpiredFileTransferLocks: () async => callOrder.add('cleanup'),
        startSocketServer: () async => callOrder.add('listen'),
        startRemoteStagingCleanup: () async => callOrder.add('staging'),
      );

      expect(
        callOrder,
        ['init', 'cleanup', 'listen', 'staging'],
      );
    });

    test('should return early when socket already running', () async {
      setAppMode(AppMode.server);

      var cleanupCalls = 0;
      var startCalls = 0;
      var stagingCalls = 0;

      await SocketServerBootstrap.start(
        initializeExecutionQueue: () async {},
        isSocketServerRunning: () => true,
        socketServerPort: () => 9000,
        cleanupExpiredFileTransferLocks: () async => cleanupCalls++,
        startSocketServer: () async => startCalls++,
        startRemoteStagingCleanup: () async => stagingCalls++,
      );

      expect(cleanupCalls, 0);
      expect(startCalls, 0);
      expect(stagingCalls, 0);
    });
  });

  group('SocketServerBootstrap.ensureListening', () {
    test('should skip listen when not in server mode', () async {
      setAppMode(AppMode.client);

      var cleanupCalls = 0;
      var startCalls = 0;

      await SocketServerBootstrap.ensureListening(
        isSocketServerRunning: () => false,
        socketServerPort: () => 9000,
        cleanupExpiredFileTransferLocks: () async => cleanupCalls++,
        startSocketServer: () async => startCalls++,
      );

      expect(cleanupCalls, 0);
      expect(startCalls, 0);
    });

    test('should start socket when server mode and not running', () async {
      setAppMode(AppMode.server);

      final callOrder = <String>[];

      await SocketServerBootstrap.ensureListening(
        isSocketServerRunning: () => false,
        socketServerPort: () => 9000,
        cleanupExpiredFileTransferLocks: () async => callOrder.add('cleanup'),
        startSocketServer: () async => callOrder.add('listen'),
      );

      expect(callOrder, ['cleanup', 'listen']);
    });
  });
}
