import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/session_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Session messages (M1.10 / PR-1)', () {
    test('createSessionRequestMessage tem payload vazio', () {
      final msg = createSessionRequestMessage(requestId: 1);
      expect(msg.header.type, MessageType.sessionRequest);
      expect(msg.payload, isEmpty);
      expect(isSessionRequestMessage(msg), isTrue);
    });

    test('createSessionResponseMessage com auth + serverId', () {
      final connectedAt = DateTime.utc(2026, 4, 19, 10);
      final now = DateTime.utc(2026, 4, 19, 12);
      final msg = createSessionResponseMessage(
        requestId: 2,
        clientId: 'client-uuid-123',
        isAuthenticated: true,
        host: '192.168.1.10',
        port: 51234,
        connectedAt: connectedAt,
        serverTimeUtc: now,
        serverId: 'server-A',
      );

      expect(msg.header.type, MessageType.sessionResponse);
      expect(msg.payload['clientId'], 'client-uuid-123');
      expect(msg.payload['isAuthenticated'], isTrue);
      expect(msg.payload['host'], '192.168.1.10');
      expect(msg.payload['port'], 51234);
      expect(msg.payload['connectedAt'], '2026-04-19T10:00:00.000Z');
      expect(msg.payload['serverTimeUtc'], '2026-04-19T12:00:00.000Z');
      expect(msg.payload['serverId'], 'server-A');
    });

    test('omite serverId quando ausente ou vazio', () {
      final msg = createSessionResponseMessage(
        requestId: 1,
        clientId: 'c1',
        isAuthenticated: false,
        host: 'localhost',
        port: 9999,
        connectedAt: DateTime.utc(2026),
        serverTimeUtc: DateTime.utc(2026),
      );
      expect(msg.payload.containsKey('serverId'), isFalse);

      final msgEmpty = createSessionResponseMessage(
        requestId: 1,
        clientId: 'c1',
        isAuthenticated: false,
        host: 'localhost',
        port: 9999,
        connectedAt: DateTime.utc(2026),
        serverTimeUtc: DateTime.utc(2026),
        serverId: '',
      );
      expect(msgEmpty.payload.containsKey('serverId'), isFalse);
    });

    test('readSessionFromResponse retorna snapshot tipado', () {
      final msg = createSessionResponseMessage(
        requestId: 1,
        clientId: 'cid',
        isAuthenticated: true,
        host: '10.0.0.5',
        port: 12345,
        connectedAt: DateTime.utc(2026, 4, 19, 10),
        serverTimeUtc: DateTime.utc(2026, 4, 19, 11),
        serverId: 'srv',
      );

      final session = readSessionFromResponse(msg);
      expect(session.clientId, 'cid');
      expect(session.isAuthenticated, isTrue);
      expect(session.host, '10.0.0.5');
      expect(session.port, 12345);
      expect(session.connectedAt, DateTime.utc(2026, 4, 19, 10));
      expect(session.serverTimeUtc, DateTime.utc(2026, 4, 19, 11));
      expect(session.serverId, 'srv');
    });

    test(
      'readSessionFromResponse aplica defaults defensivos em payload vazio',
      () {
        final msg = Message(
          header: MessageHeader(
            type: MessageType.sessionResponse,
            length: 0,
            requestId: 1,
          ),
          payload: const <String, dynamic>{},
          checksum: 0,
        );

        final session = readSessionFromResponse(msg);
        expect(session.clientId, isEmpty);
        expect(session.isAuthenticated, isFalse);
        expect(session.host, isEmpty);
        expect(session.port, 0);
        expect(session.connectedAt.isUtc, isTrue);
        expect(session.serverTimeUtc.isUtc, isTrue);
        expect(session.serverId, isNull);
      },
    );

    test('connectedAt e serverTimeUtc sao sempre serializados em UTC', () {
      final localTime = DateTime(2026, 4, 19, 9, 30); // local
      final msg = createSessionResponseMessage(
        requestId: 1,
        clientId: 'c1',
        isAuthenticated: true,
        host: 'h',
        port: 1,
        connectedAt: localTime,
        serverTimeUtc: localTime,
      );

      final connectedAtRaw = msg.payload['connectedAt'] as String;
      final serverTimeRaw = msg.payload['serverTimeUtc'] as String;
      expect(connectedAtRaw.endsWith('Z'), isTrue);
      expect(serverTimeRaw.endsWith('Z'), isTrue);
    });
  });
}
