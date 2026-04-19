import 'package:backup_database/infrastructure/protocol/capabilities_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/protocol_versions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Capabilities messages (M1.3 / M4.1)', () {
    test('createCapabilitiesRequestMessage tem payload vazio', () {
      final msg = createCapabilitiesRequestMessage();
      expect(msg.header.type, MessageType.capabilitiesRequest);
      expect(msg.payload, isEmpty);
      expect(isCapabilitiesRequestMessage(msg), isTrue);
    });

    test(
      'createCapabilitiesResponseMessage carrega todos campos obrigatorios',
      () {
        final clock = DateTime.utc(2026, 4, 19, 12);
        final msg = createCapabilitiesResponseMessage(
          requestId: 2,
          protocolVersion: 1,
          wireVersion: kCurrentWireVersion,
          supportsRunId: true,
          supportsResume: true,
          supportsArtifactRetention: false,
          supportsChunkAck: false,
          supportsExecutionQueue: false,
          chunkSize: 65536,
          compression: 'gzip',
          serverTimeUtc: clock,
        );

        expect(msg.header.type, MessageType.capabilitiesResponse);
        expect(msg.payload['protocolVersion'], 1);
        expect(msg.payload['wireVersion'], kCurrentWireVersion);
        expect(msg.payload['supportsRunId'], isTrue);
        expect(msg.payload['supportsResume'], isTrue);
        expect(msg.payload['supportsArtifactRetention'], isFalse);
        expect(msg.payload['supportsChunkAck'], isFalse);
        expect(msg.payload['supportsExecutionQueue'], isFalse);
        expect(msg.payload['chunkSize'], 65536);
        expect(msg.payload['compression'], 'gzip');
        expect(msg.payload['serverTimeUtc'], '2026-04-19T12:00:00.000Z');
      },
    );

    test('readCapabilitiesFromResponse retorna snapshot tipado', () {
      final msg = createCapabilitiesResponseMessage(
        requestId: 1,
        protocolVersion: 2,
        wireVersion: 1,
        supportsRunId: true,
        supportsResume: true,
        supportsArtifactRetention: true,
        supportsChunkAck: false,
        supportsExecutionQueue: true,
        chunkSize: 32768,
        compression: 'gzip',
        serverTimeUtc: DateTime.utc(2026, 4, 19, 10),
      );

      final caps = readCapabilitiesFromResponse(msg);
      expect(caps.protocolVersion, 2);
      expect(caps.wireVersion, 1);
      expect(caps.supportsRunId, isTrue);
      expect(caps.supportsResume, isTrue);
      expect(caps.supportsArtifactRetention, isTrue);
      expect(caps.supportsChunkAck, isFalse);
      expect(caps.supportsExecutionQueue, isTrue);
      expect(caps.chunkSize, 32768);
      expect(caps.compression, 'gzip');
      expect(caps.serverTimeUtc, DateTime.utc(2026, 4, 19, 10));
    });

    test(
      'readCapabilitiesFromResponse usa defaults em payload parcial '
      '(servidor v1 com campos novos faltando)',
      () {
        // Simula servidor mais antigo que so devolve subset minimo
        final partial = Message(
          header: MessageHeader(
            type: MessageType.capabilitiesResponse,
            length: 0,
            requestId: 1,
          ),
          payload: <String, dynamic>{
            'protocolVersion': 1,
          },
          checksum: 0,
        );

        final caps = readCapabilitiesFromResponse(partial);
        expect(caps.protocolVersion, 1);
        expect(caps.wireVersion, kCurrentWireVersion);
        expect(caps.supportsRunId, isFalse);
        expect(caps.supportsResume, isTrue, reason: 'default conservador');
        expect(caps.supportsArtifactRetention, isFalse);
        expect(caps.supportsChunkAck, isFalse);
        expect(caps.supportsExecutionQueue, isFalse);
        expect(caps.chunkSize, 65536);
        expect(caps.compression, 'gzip');
        expect(caps.serverTimeUtc, isNull);
      },
    );

    test(
      'readCapabilitiesFromResponse tolera serverTimeUtc invalido',
      () {
        final msg = Message(
          header: MessageHeader(
            type: MessageType.capabilitiesResponse,
            length: 0,
            requestId: 1,
          ),
          payload: const <String, dynamic>{
            'protocolVersion': 1,
            'serverTimeUtc': 'not-a-date',
          },
          checksum: 0,
        );

        final caps = readCapabilitiesFromResponse(msg);
        expect(caps.serverTimeUtc, isNull);
      },
    );

    test('ServerCapabilities.legacyDefault e seguro para servidor v1', () {
      const legacy = ServerCapabilities.legacyDefault;
      expect(legacy.protocolVersion, 1);
      expect(legacy.wireVersion, kCurrentWireVersion);
      // Defaults conservadores: nada novo habilitado por engano
      expect(legacy.supportsRunId, isFalse);
      expect(legacy.supportsArtifactRetention, isFalse);
      expect(legacy.supportsChunkAck, isFalse);
      expect(legacy.supportsExecutionQueue, isFalse);
      // Mas mantem features ja existentes em v1
      expect(legacy.supportsResume, isTrue);
    });

    test(
      'serverTimeUtc em payload e sempre serializado em ISO 8601 UTC',
      () {
        final localTime = DateTime(2026, 4, 19, 9, 30); // local time
        final msg = createCapabilitiesResponseMessage(
          requestId: 1,
          protocolVersion: 1,
          wireVersion: 1,
          supportsRunId: false,
          supportsResume: true,
          supportsArtifactRetention: false,
          supportsChunkAck: false,
          supportsExecutionQueue: false,
          chunkSize: 65536,
          compression: 'gzip',
          serverTimeUtc: localTime,
        );

        final raw = msg.payload['serverTimeUtc'] as String;
        // Deve terminar com Z (UTC) e ser parseavel
        expect(raw.endsWith('Z'), isTrue);
        final parsed = DateTime.parse(raw);
        expect(parsed.isUtc, isTrue);
      },
    );
  });
}
