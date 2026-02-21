import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/infrastructure/protocol/auth_messages.dart';
import 'package:backup_database/infrastructure/protocol/binary_protocol.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/heartbeat.dart';
import 'package:backup_database/infrastructure/socket/server/client_handler.dart';
import 'package:backup_database/infrastructure/socket/server/server_authentication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockServerAuthentication extends Mock implements ServerAuthentication {}

Future<({Socket client, Socket server})> createSocketPair() async {
  final serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = serverSocket.port;
  final clientFuture = Socket.connect(InternetAddress.loopbackIPv4, port);
  final serverFuture = serverSocket.first;
  final results = await Future.wait(<Future<dynamic>>[
    clientFuture,
    serverFuture,
  ]);
  final client = results[0] as Socket;
  final server = results[1] as Socket;
  await serverSocket.close();
  return (client: client, server: server);
}

Message _dummyMessage() => Message(
  header: MessageHeader(type: MessageType.heartbeat, length: 0),
  payload: <String, dynamic>{},
  checksum: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BinaryProtocol protocol;

  setUpAll(() {
    registerFallbackValue(_dummyMessage());
  });

  setUp(() {
    protocol = BinaryProtocol();
  });

  group('ClientHandler', () {
    test(
      'without authentication should be authenticated after start',
      () async {
        final pair = await createSocketPair();
        addTearDown(() {
          pair.client.destroy();
          pair.server.destroy();
        });

        String? disconnectedId;
        final handler = ClientHandler(
          socket: pair.server,
          protocol: protocol,
          onDisconnect: (id) => disconnectedId = id,
        );
        handler.start();

        expect(handler.isAuthenticated, isTrue);
        expect(handler.clientId, isNotEmpty);
        expect(handler.host, isNotEmpty);
        expect(handler.port, greaterThan(0));
        expect(disconnectedId, isNull);

        handler.disconnect();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(disconnectedId, equals(handler.clientId));
      },
    );

    test('should receive message and emit on messageStream', () async {
      final pair = await createSocketPair();
      addTearDown(() {
        pair.client.destroy();
        pair.server.destroy();
      });

      final handler = ClientHandler(
        socket: pair.server,
        protocol: protocol,
        onDisconnect: (_) {},
      );
      handler.start();

      Message? received;
      final sub = handler.messageStream.listen((m) {
        received = m;
      });

      final heartbeat = createHeartbeatMessage();
      final bytes = protocol.serializeMessage(heartbeat);
      pair.client.add(bytes);
      await pair.client.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(received, isNotNull);
      expect(received!.header.type, MessageType.heartbeat);
      await sub.cancel();
      handler.disconnect();
    });

    test('send should serialize and write to socket', () async {
      final pair = await createSocketPair();
      addTearDown(() {
        pair.client.destroy();
        pair.server.destroy();
      });

      final handler = ClientHandler(
        socket: pair.server,
        protocol: protocol,
        onDisconnect: (_) {},
      );
      handler.start();

      final msg = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 0),
        payload: <String, dynamic>{},
        checksum: 0,
      );
      await handler.send(msg);

      final completer = Completer<Message>.sync();
      final buffer = <int>[];
      void onData(List<int> data) {
        buffer.addAll(data);
        if (buffer.length >= 16 + 4) {
          final length =
              (buffer[5] << 24) |
              (buffer[6] << 16) |
              (buffer[7] << 8) |
              buffer[8];
          final total = 16 + length + 4;
          if (buffer.length >= total) {
            try {
              final message = protocol.deserializeMessage(
                Uint8List.fromList(buffer.sublist(0, total)),
              );
              if (!completer.isCompleted) completer.complete(message);
            } on Object catch (_) {}
          }
        }
      }

      pair.client.listen(onData);
      final received = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('No message received'),
      );
      expect(received.header.type, MessageType.heartbeat);
      handler.disconnect();
    });

    test('disconnect should call onDisconnect and close stream', () async {
      final pair = await createSocketPair();
      addTearDown(() {
        pair.client.destroy();
        pair.server.destroy();
      });

      String? disconnectedId;
      final handler = ClientHandler(
        socket: pair.server,
        protocol: protocol,
        onDisconnect: (id) => disconnectedId = id,
      );
      handler.start();
      final clientId = handler.clientId;

      var streamDone = false;
      handler.messageStream.listen(
        null,
        onDone: () => streamDone = true,
      );

      handler.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(disconnectedId, equals(clientId));
      expect(streamDone, isTrue);
    });

    test(
      'with authentication valid authRequest should get authResponse',
      () async {
        final pair = await createSocketPair();
        addTearDown(() {
          pair.client.destroy();
          pair.server.destroy();
        });

        final mockAuth = MockServerAuthentication();
        when(
          () => mockAuth.validateAuthRequest(any()),
        ).thenAnswer((_) async => const AuthValidationResult(isValid: true));

        final handler = ClientHandler(
          socket: pair.server,
          protocol: protocol,
          onDisconnect: (_) {},
          authentication: mockAuth,
        );
        handler.start();

        final authReceived = Completer<void>.sync();
        handler.messageStream.listen((m) {
          if (m.header.type == MessageType.authRequest &&
              !authReceived.isCompleted) {
            authReceived.complete();
          }
        });

        final authRequest = createAuthRequest(
          serverId: 'srv-1',
          passwordHash: 'hash',
        );
        final bytes = protocol.serializeMessage(authRequest);
        pair.client.add(bytes);
        await pair.client.flush();

        final responseCompleter = Completer<Message>.sync();
        final buffer = <int>[];
        void onData(List<int> data) {
          buffer.addAll(data);
          if (buffer.length >= 16 + 4) {
            final length =
                (buffer[5] << 24) |
                (buffer[6] << 16) |
                (buffer[7] << 8) |
                buffer[8];
            final total = 16 + length + 4;
            if (buffer.length >= total) {
              try {
                final message = protocol.deserializeMessage(
                  Uint8List.fromList(buffer.sublist(0, total)),
                );
                if (message.header.type == MessageType.authResponse &&
                    !responseCompleter.isCompleted) {
                  responseCompleter.complete(message);
                }
              } on Object catch (_) {}
            }
          }
        }

        pair.client.listen(onData);

        final response = await responseCompleter.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw TimeoutException('No authResponse'),
        );
        expect(response.header.type, MessageType.authResponse);
        expect(response.payload['success'], isTrue);
        verify(() => mockAuth.validateAuthRequest(any())).called(1);
        await authReceived.future.timeout(
          const Duration(seconds: 1),
          onTimeout: () => throw TimeoutException('Auth message not emitted'),
        );
        handler.disconnect();
      },
    );

    test(
      'toConnectedClient returns ConnectedClient with correct fields',
      () async {
        final pair = await createSocketPair();
        addTearDown(() {
          pair.client.destroy();
          pair.server.destroy();
        });

        final handler = ClientHandler(
          socket: pair.server,
          protocol: protocol,
          onDisconnect: (_) {},
        );
        handler.start();
        handler.clientName = 'TestClient';
        final connectedAt = DateTime.now();

        final client = handler.toConnectedClient(connectedAt);

        expect(client.id, equals(handler.clientId));
        expect(client.clientName, equals('TestClient'));
        expect(client.host, equals(handler.host));
        expect(client.port, equals(handler.port));
        expect(client.connectedAt, equals(connectedAt));
        expect(client.isAuthenticated, isTrue);
        handler.disconnect();
      },
    );
  });
}
