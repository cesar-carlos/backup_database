import 'dart:io';

import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/client/tcp_socket_client.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:flutter_test/flutter_test.dart';

int _nextPort = 29650;

int getPort() {
  final p = _nextPort;
  _nextPort++;
  return p;
}

void main() {
  late SocketServerService server;

  setUpAll(() {
    if (!di.getIt.isRegistered<SocketLoggerService>()) {
      di.getIt.registerSingleton<SocketLoggerService>(
        SocketLoggerService(logsDirectory: Directory.systemTemp.path),
      );
    }
  });

  setUp(() {
    server = TcpSocketServer();
  });

  tearDown(() async {
    await server.stop();
  });

  group('TcpSocketServer', () {
    test('should start and stop on default port', () async {
      await server.start();
      expect(server.isRunning, isTrue);
      expect(server.port, 9527);

      await server.stop();
      expect(server.isRunning, isFalse);
    });

    test('should start on custom port', () async {
      await server.start(port: 19527);
      expect(server.isRunning, isTrue);
      expect(server.port, 19527);

      await server.stop();
    });

    test('getConnectedClients should return empty when no clients', () async {
      await server.start();
      final clients = await server.getConnectedClients();
      expect(clients, isEmpty);
      await server.stop();
    });

    test('should not start twice', () async {
      await server.start();
      await server.start();
      expect(server.isRunning, isTrue);
      await server.stop();
    });

    test('multiple connections should be tracked', () async {
      final port = getPort();
      await server.start(port: port);
      final client1 = TcpSocketClient();
      final client2 = TcpSocketClient();
      addTearDown(client1.disconnect);
      addTearDown(client2.disconnect);

      await client1.connect(host: '127.0.0.1', port: port);
      await client2.connect(host: '127.0.0.1', port: port);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      var clients = await server.getConnectedClients();
      expect(clients.length, 2);

      await client1.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      clients = await server.getConnectedClients();
      expect(clients.length, 1);
    });

    test('sendToClient delivers message to connected client', () async {
      final port = getPort();
      await server.start(port: port);
      final socketClient = TcpSocketClient();
      addTearDown(socketClient.disconnect);
      await socketClient.connect(host: '127.0.0.1', port: port);

      Message? received;
      final sub = socketClient.messageStream.listen((m) {
        received = m;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final clients = await server.getConnectedClients();
      expect(clients.length, 1);

      final msg = Message(
        header: MessageHeader(type: MessageType.disconnect, length: 0),
        payload: <String, dynamic>{},
        checksum: 0,
      );
      await server.sendToClient(clients.first.id, msg);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(received, isNotNull);
      expect(received!.header.type, MessageType.disconnect);
      await sub.cancel();
    });
  });
}
