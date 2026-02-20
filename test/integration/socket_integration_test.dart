import 'dart:io';

import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/core/security/password_hasher.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/client/socket_client_service.dart';
import 'package:backup_database/infrastructure/socket/client/tcp_socket_client.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

int _nextPort = 29527;

int getTestPort() {
  final port = _nextPort;
  _nextPort++;
  return port;
}

Future<void> _waitForAuthStatus(
  TcpSocketClient client, {
  Duration timeout = const Duration(seconds: 3),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (client.status == ConnectionStatus.connected ||
        client.status == ConnectionStatus.authenticationFailed) {
      return;
    }
    await Future<void>.delayed(pollInterval);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TcpSocketServer server;
  late TcpSocketClient client;
  late int testPort;

  setUpAll(() {
    if (!di.getIt.isRegistered<SocketLoggerService>()) {
      di.getIt.registerSingleton<SocketLoggerService>(
        SocketLoggerService(logsDirectory: Directory.systemTemp.path),
      );
    }
  });

  setUp(() async {
    server = TcpSocketServer();
    client = TcpSocketClient();
    testPort = getTestPort();
  });

  tearDown(() async {
    await client.disconnect();
    await server.stop();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  group('Socket Integration', () {
    test(
      'Server start → Client connect (no auth) → getConnectedClients → Disconnect',
      () async {
        await server.start(port: testPort);
        expect(server.isRunning, isTrue);
        expect(server.port, testPort);

        await client.connect(host: '127.0.0.1', port: testPort);
        expect(client.isConnected, isTrue);
        expect(client.status, ConnectionStatus.connected);

        await Future<void>.delayed(const Duration(milliseconds: 100));
        final clients = await server.getConnectedClients();
        expect(clients.length, 1);
        expect(clients.first.isAuthenticated, isTrue);

        await client.disconnect();
        expect(client.isConnected, isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final afterDisconnect = await server.getConnectedClients();
        expect(afterDisconnect.length, 0);
      },
    );

    test('Client receives message from server', () async {
      await server.start(port: testPort);
      Message? received;
      final sub = client.messageStream.listen((m) {
        received = m;
      });

      await client.connect(host: '127.0.0.1', port: testPort);
      expect(client.isConnected, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final clients = await server.getConnectedClients();
      expect(clients.length, 1);
      final clientId = clients.first.id;

      final testMessage = Message(
        header: MessageHeader(
          type: MessageType.metricsRequest,
          length: 2,
        ),
        payload: <String, dynamic>{'t': 1},
        checksum: 0,
      );
      await server.sendToClient(clientId, testMessage);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(received, isNotNull);
      expect(received!.header.type, MessageType.metricsRequest);
      await sub.cancel();
    });

    test('Server broadcastToAll reaches connected client', () async {
      await server.start(port: testPort);
      Message? received;
      final sub = client.messageStream.listen((m) {
        received = m;
      });

      await client.connect(host: '127.0.0.1', port: testPort);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final msg = Message(
        header: MessageHeader(type: MessageType.disconnect, length: 0),
        payload: <String, dynamic>{},
        checksum: 0,
      );
      await server.broadcastToAll(msg);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(received, isNotNull);
      expect(received!.header.type, MessageType.disconnect);
      await sub.cancel();
    });

    test(
      'Client connect with auth (serverId + password) → authenticated',
      () async {
        final db = AppDatabase.inMemory();
        addTearDown(db.close);

        const serverId = 'test-server-123';
        const password = 'test-password';
        final passwordHash = PasswordHasher.hash(password, serverId);
        await db.serverCredentialDao.insertCredential(
          ServerCredentialsTableCompanion.insert(
            id: const Uuid().v4(),
            serverId: serverId,
            passwordHash: passwordHash,
            name: 'Test Server',
            createdAt: DateTime.now(),
          ),
        );

        final serverWithAuth = TcpSocketServer(
          serverCredentialDao: db.serverCredentialDao,
        );
        await serverWithAuth.start(port: testPort);
        addTearDown(() async {
          await serverWithAuth.stop();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });

        final authClient = TcpSocketClient();
        addTearDown(authClient.disconnect);

        await authClient.connect(
          host: '127.0.0.1',
          port: testPort,
          serverId: serverId,
          password: password,
        );
        await _waitForAuthStatus(authClient);
        expect(authClient.isConnected, isTrue);
        expect(authClient.status, ConnectionStatus.connected);

        await Future<void>.delayed(const Duration(milliseconds: 100));
        final clients = await serverWithAuth.getConnectedClients();
        expect(clients.length, 1);
        expect(clients.first.isAuthenticated, isTrue);
      },
    );

    test('Client connect with wrong password → authenticationFailed', () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);

      const serverId = 'test-server-auth';
      const password = 'correct-password';
      final passwordHash = PasswordHasher.hash(password, serverId);
      await db.serverCredentialDao.insertCredential(
        ServerCredentialsTableCompanion.insert(
          id: const Uuid().v4(),
          serverId: serverId,
          passwordHash: passwordHash,
          name: 'Test',
          createdAt: DateTime.now(),
        ),
      );

      final serverWithAuth = TcpSocketServer(
        serverCredentialDao: db.serverCredentialDao,
      );
      await serverWithAuth.start(port: testPort);
      addTearDown(() async {
        await serverWithAuth.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      final authClient = TcpSocketClient();
      addTearDown(authClient.disconnect);

      await authClient.connect(
        host: '127.0.0.1',
        port: testPort,
        serverId: serverId,
        password: 'wrong-password',
      );
      await _waitForAuthStatus(authClient);
      expect(authClient.isConnected, isFalse);
      expect(
        authClient.status,
        anyOf(
          ConnectionStatus.authenticationFailed,
          ConnectionStatus.disconnected,
        ),
      );
    });

    test('Auth then stays connected (heartbeat path)', () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      const serverId = 'heartbeat-server';
      const password = 'heartbeat-pw';
      final passwordHash = PasswordHasher.hash(password, serverId);
      await db.serverCredentialDao.insertCredential(
        ServerCredentialsTableCompanion.insert(
          id: const Uuid().v4(),
          serverId: serverId,
          passwordHash: passwordHash,
          name: 'Heartbeat Test',
          createdAt: DateTime.now(),
        ),
      );
      final serverWithAuth = TcpSocketServer(
        serverCredentialDao: db.serverCredentialDao,
      );
      await serverWithAuth.start(port: testPort);
      addTearDown(() async {
        await serverWithAuth.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      final authClient = TcpSocketClient();
      addTearDown(authClient.disconnect);
      await authClient.connect(
        host: '127.0.0.1',
        port: testPort,
        serverId: serverId,
        password: password,
      );
      await _waitForAuthStatus(authClient);
      expect(authClient.isConnected, isTrue);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(authClient.isConnected, isTrue);
    });

    test('Multiple clients receive broadcastToAll', () async {
      await server.start(port: testPort);
      final clientA = TcpSocketClient();
      final clientB = TcpSocketClient();
      addTearDown(clientA.disconnect);
      addTearDown(clientB.disconnect);
      await clientA.connect(host: '127.0.0.1', port: testPort);
      await clientB.connect(host: '127.0.0.1', port: testPort);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      Message? receivedA;
      Message? receivedB;
      final subA = clientA.messageStream.listen((m) {
        receivedA = m;
      });
      final subB = clientB.messageStream.listen((m) {
        receivedB = m;
      });
      final msg = Message(
        header: MessageHeader(type: MessageType.metricsRequest, length: 0),
        payload: <String, dynamic>{},
        checksum: 0,
      );
      await server.broadcastToAll(msg);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(receivedA, isNotNull);
      expect(receivedB, isNotNull);
      expect(receivedA!.header.type, MessageType.metricsRequest);
      expect(receivedB!.header.type, MessageType.metricsRequest);
      await subA.cancel();
      await subB.cancel();
    });

    test(
      'Server stop then restart, client with autoReconnect reconnects',
      () async {
        await server.start(port: testPort);
        final reconnectingClient = TcpSocketClient();
        addTearDown(reconnectingClient.disconnect);
        await reconnectingClient.connect(
          host: '127.0.0.1',
          port: testPort,
          enableAutoReconnect: true,
        );
        expect(reconnectingClient.isConnected, isTrue);
        await server.stop();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final server2 = TcpSocketServer();
        await server2.start(port: testPort);
        addTearDown(() async {
          await server2.stop();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while (DateTime.now().isBefore(deadline)) {
          if (reconnectingClient.status == ConnectionStatus.connected) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(reconnectingClient.isConnected, isTrue);
      },
    );
  });
}
