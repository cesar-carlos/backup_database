import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/session_messages.dart';
import 'package:backup_database/infrastructure/socket/server/session_message_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionMessageHandler', () {
    test(
      'responde sessionResponse com snapshot do cliente quando ele existe',
      () async {
        final connectedAt = DateTime.utc(2026, 4, 19, 10);
        final now = DateTime.utc(2026, 4, 19, 11);

        final handler = SessionMessageHandler(
          sessionLookup: (cid) async => SessionInfo(
            clientId: cid,
            isAuthenticated: true,
            host: '127.0.0.1',
            port: 51111,
            connectedAt: connectedAt,
            serverId: 'srv-1',
          ),
          clock: () => now,
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'client-X',
          createSessionRequestMessage(requestId: 7),
          capture,
        );

        expect(sent, isNotNull);
        expect(sent!.header.type, MessageType.sessionResponse);
        expect(sent!.header.requestId, 7);
        final session = readSessionFromResponse(sent!);
        expect(session.clientId, 'client-X');
        expect(session.isAuthenticated, isTrue);
        expect(session.host, '127.0.0.1');
        expect(session.port, 51111);
        expect(session.connectedAt, connectedAt);
        expect(session.serverTimeUtc, now);
        expect(session.serverId, 'srv-1');
      },
    );

    test(
      'responde error padronizado quando lookup retorna null (cliente desconectou)',
      () async {
        final handler = SessionMessageHandler(
          sessionLookup: (cid) async => null,
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'client-gone',
          createSessionRequestMessage(requestId: 1),
          capture,
        );

        expect(sent, isNotNull);
        expect(sent!.header.type, MessageType.error);
        expect(getErrorFromMessage(sent!), contains('client-gone'));
        // ErrorCode generico — proxima fase pode adicionar SESSION_NOT_FOUND
        expect(getErrorCodeFromMessage(sent!), ErrorCode.unknown);
      },
    );

    test('ignora mensagens que nao sao sessionRequest', () async {
      final handler = SessionMessageHandler(
        sessionLookup: (cid) async => SessionInfo(
          clientId: cid,
          isAuthenticated: true,
          host: 'h',
          port: 1,
          connectedAt: DateTime.utc(2026),
        ),
      );

      Message? sent;
      Future<void> capture(String c, Message m) async => sent = m;

      final notRequest = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 0),
        payload: const <String, dynamic>{},
        checksum: 0,
      );

      await handler.handle('c1', notRequest, capture);
      expect(sent, isNull);
    });

    test(
      'lookup que lanca excecao -> responde error sem crashar handler',
      () async {
        final handler = SessionMessageHandler(
          sessionLookup: (cid) async => throw Exception('lookup boom'),
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'c1',
          createSessionRequestMessage(requestId: 1),
          capture,
        );

        expect(sent, isNotNull);
        expect(sent!.header.type, MessageType.error);
        expect(getErrorFromMessage(sent!), contains('Falha ao consultar'));
      },
    );

    test('cliente sem auth -> isAuthenticated=false na resposta', () async {
      final handler = SessionMessageHandler(
        sessionLookup: (cid) async => SessionInfo(
          clientId: cid,
          isAuthenticated: false,
          host: 'h',
          port: 1,
          connectedAt: DateTime.utc(2026),
        ),
      );

      Message? sent;
      Future<void> capture(String c, Message m) async => sent = m;

      await handler.handle(
        'c1',
        createSessionRequestMessage(),
        capture,
      );

      final session = readSessionFromResponse(sent!);
      expect(session.isAuthenticated, isFalse);
      expect(session.serverId, isNull);
    });
  });
}
