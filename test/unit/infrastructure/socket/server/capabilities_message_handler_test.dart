import 'package:backup_database/infrastructure/protocol/capabilities_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/protocol_versions.dart';
import 'package:backup_database/infrastructure/socket/server/capabilities_message_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CapabilitiesMessageHandler', () {
    test(
      'responde capabilitiesResponse com versoes correntes do protocolo',
      () async {
        final fixedNow = DateTime.utc(2026, 4, 19, 12);
        final handler = CapabilitiesMessageHandler(clock: () => fixedNow);

        Message? sent;
        Future<void> capture(String clientId, Message msg) async {
          sent = msg;
        }

        await handler.handle(
          'client-1',
          createCapabilitiesRequestMessage(requestId: 42),
          capture,
        );

        expect(sent, isNotNull);
        expect(sent!.header.type, MessageType.capabilitiesResponse);
        expect(sent!.header.requestId, 42);

        final caps = readCapabilitiesFromResponse(sent!);
        expect(caps.protocolVersion, kCurrentProtocolVersion);
        expect(caps.wireVersion, kCurrentWireVersion);
        expect(caps.serverTimeUtc, fixedNow);
      },
    );

    test(
      'reflete features ja entregues: runId, resume, retencao, fila; '
      'nega chunkAck (ADR-002)',
      () async {
        final handler = CapabilitiesMessageHandler();
        Message? sent;
        Future<void> capture(String clientId, Message msg) async {
          sent = msg;
        }

        await handler.handle(
          'client-X',
          createCapabilitiesRequestMessage(requestId: 1),
          capture,
        );

        final caps = readCapabilitiesFromResponse(sent!);
        expect(caps.supportsRunId, isTrue);
        expect(caps.supportsResume, isTrue);
        expect(caps.supportsArtifactRetention, isTrue);
        expect(caps.supportsChunkAck, isFalse);
        expect(caps.supportsExecutionQueue, isTrue);
      },
    );

    test('ignora mensagens que nao sao capabilitiesRequest', () async {
      final handler = CapabilitiesMessageHandler();
      Message? sent;
      Future<void> capture(String clientId, Message msg) async {
        sent = msg;
      }

      // Manda heartbeat (nao deveria ser respondido pelo capabilities handler)
      final notRequest = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 0),
        payload: const <String, dynamic>{},
        checksum: 0,
      );

      await handler.handle('client-X', notRequest, capture);

      expect(sent, isNull);
    });

    test('chunkSize e compression sao configuraveis no construtor', () async {
      final handler = CapabilitiesMessageHandler(
        chunkSize: 8192,
        compression: 'none',
      );
      Message? sent;
      Future<void> capture(String clientId, Message msg) async {
        sent = msg;
      }

      await handler.handle(
        'c1',
        createCapabilitiesRequestMessage(requestId: 1),
        capture,
      );

      final caps = readCapabilitiesFromResponse(sent!);
      expect(caps.chunkSize, 8192);
      expect(caps.compression, 'none');
    });
  });
}
