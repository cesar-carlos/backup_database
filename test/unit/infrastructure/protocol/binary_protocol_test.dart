import 'dart:typed_data';

import 'package:backup_database/infrastructure/protocol/binary_protocol.dart';
import 'package:backup_database/infrastructure/protocol/compression.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BinaryProtocol', () {
    test('should serialize and deserialize message round-trip without compression', () {
      final protocol = BinaryProtocol();
      final message = Message(
        header: MessageHeader(
          type: MessageType.heartbeat,
          length: 10,
        ),
        payload: <String, dynamic>{'ts': 1234567890},
        checksum: 0,
      );

      final bytes = protocol.serializeMessage(message);
      expect(bytes.length, greaterThanOrEqualTo(16 + 4));

      final restored = protocol.deserializeMessage(bytes);
      expect(restored.header.type, message.header.type);
      expect(restored.payload['ts'], message.payload['ts']);
    });

    test('should throw ProtocolException when data too short', () {
      final protocol = BinaryProtocol();
      final shortData = Uint8List(10);

      expect(
        () => protocol.deserializeMessage(shortData),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('should throw ProtocolException when magic invalid', () {
      final protocol = BinaryProtocol();
      final buffer = Uint8List(16 + 4);
      buffer[0] = 0x00;
      buffer[1] = 0x00;
      buffer[2] = 0x00;
      buffer[3] = 0x00;

      expect(
        () => protocol.deserializeMessage(buffer),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('should throw ProtocolException when checksum mismatch', () {
      final protocol = BinaryProtocol();
      final message = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 2),
        payload: <String, dynamic>{'x': 1},
        checksum: 0,
      );
      final bytes = protocol.serializeMessage(message);
      final lastOffset = bytes.length - 4;
      bytes[lastOffset] ^= 0xFF;

      expect(
        () => protocol.deserializeMessage(bytes),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('should serialize and deserialize with compression when payload large', () {
      final protocol = BinaryProtocol(compression: PayloadCompression());
      final largePayload = <String, dynamic>{
        'data': 'x' * 2000,
      };
      final payloadJson = '{"data":"${'x' * 2000}"}';
      final message = Message(
        header: MessageHeader(
          type: MessageType.fileChunk,
          length: payloadJson.length,
        ),
        payload: largePayload,
        checksum: 0,
      );

      final bytes = protocol.serializeMessage(message);
      final restored = protocol.deserializeMessage(bytes);

      expect(restored.header.type, MessageType.fileChunk);
      expect(restored.payload['data'], largePayload['data']);
    });

    test('calculateChecksum should match Crc32 of payload', () {
      final protocol = BinaryProtocol();
      final message = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 2),
        payload: <String, dynamic>{'a': 1},
        checksum: 0,
      );
      final bytes = protocol.serializeMessage(message);
      final payloadLength = bytes.length - 16 - 4;
      final payloadBytes = Uint8List.sublistView(bytes, 16, 16 + payloadLength);
      final expectedChecksum = protocol.calculateChecksum(payloadBytes);
      final storedChecksum = ByteData.sublistView(
        bytes,
        bytes.length - 4,
        bytes.length,
      ).getUint32(0);

      expect(protocol.validateChecksum(payloadBytes, storedChecksum), isTrue);
      expect(storedChecksum, expectedChecksum);
    });
  });
}
