import 'dart:io';

import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/client/socket_client_service.dart';
import 'package:backup_database/infrastructure/socket/client/tcp_socket_client.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:flutter_test/flutter_test.dart';

int _nextPort = 29600;

int getPort() {
  final p = _nextPort;
  _nextPort++;
  return p;
}

void main() {
  late TcpSocketClient client;

  setUp(() {
    client = TcpSocketClient();
  });

  tearDown(() async {
    await client.disconnect();
  });

  group('TcpSocketClient', () {
    test('should have disconnected status when not connected', () {
      expect(client.isConnected, isFalse);
      expect(client.status, ConnectionStatus.disconnected);
    });

    test('disconnect when not connected should not throw', () async {
      await client.disconnect();
      expect(client.status, ConnectionStatus.disconnected);
    });

    test('send when not connected should throw StateError', () async {
      final msg = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 2),
        payload: <String, dynamic>{'t': 1},
        checksum: 0,
      );
      expect(
        () => client.send(msg),
        throwsA(isA<StateError>()),
      );
    });

    test('connect to invalid port should fail and set error status', () async {
      try {
        await client.connect(host: '127.0.0.1', port: 1);
      } on SocketException catch (_) {
        // Expected when no server on port 1
      } on Object catch (_) {}
      expect(client.isConnected, isFalse);
      expect(
        client.status == ConnectionStatus.error ||
            client.status == ConnectionStatus.disconnected,
        isTrue,
      );
    });

    test('connect then disconnect should work with real server', () async {
      final server = TcpSocketServer();
      final port = getPort();
      await server.start(port: port);
      addTearDown(() async {
        await server.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      await client.connect(host: '127.0.0.1', port: port);
      expect(client.isConnected, isTrue);
      expect(client.status, ConnectionStatus.connected);

      await client.disconnect();
      expect(client.isConnected, isFalse);
      expect(client.status, ConnectionStatus.disconnected);
    });

    test('messageStream should emit messages received from server', () async {
      final server = TcpSocketServer();
      final port = getPort();
      await server.start(port: port);
      addTearDown(() async {
        await server.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      await client.connect(host: '127.0.0.1', port: port);
      Message? received;
      final sub = client.messageStream.listen((m) {
        received = m;
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final clients = await server.getConnectedClients();
      expect(clients.length, 1);
      final msg = Message(
        header: MessageHeader(type: MessageType.metricsRequest, length: 2),
        payload: <String, dynamic>{'x': 1},
        checksum: 0,
      );
      await server.sendToClient(clients.first.id, msg);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(received, isNotNull);
      expect(received!.header.type, MessageType.metricsRequest);
      await sub.cancel();
    });

    test('reconnect after server restarts when enableAutoReconnect true', () async {
      final server = TcpSocketServer();
      final port = getPort();
      await server.start(port: port);
      addTearDown(() async {
        await server.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      final reconnectingClient = TcpSocketClient();
      addTearDown(reconnectingClient.disconnect);
      await reconnectingClient.connect(
        host: '127.0.0.1',
        port: port,
        enableAutoReconnect: true,
      );
      expect(reconnectingClient.isConnected, isTrue);

      await server.stop();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final server2 = TcpSocketServer();
      await server2.start(port: port);
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
      expect(reconnectingClient.status, ConnectionStatus.connected);
    });

    test('when server stops and does not restart, client becomes disconnected', () async {
      final server = TcpSocketServer();
      final port = getPort();
      await server.start(port: port);
      final reconnectingClient = TcpSocketClient();
      addTearDown(reconnectingClient.disconnect);
      await reconnectingClient.connect(
        host: '127.0.0.1',
        port: port,
        enableAutoReconnect: true,
      );
      expect(reconnectingClient.isConnected, isTrue);
      await server.stop();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(reconnectingClient.isConnected, isFalse);
      expect(
        reconnectingClient.status == ConnectionStatus.disconnected ||
            reconnectingClient.status == ConnectionStatus.error,
        isTrue,
      );
    });
  });
}
