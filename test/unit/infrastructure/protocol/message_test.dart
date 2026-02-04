import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageHeader', () {
    test('should create header with required fields', () {
      final header = MessageHeader(
        type: MessageType.heartbeat,
        length: 10,
      );

      expect(header.type, MessageType.heartbeat);
      expect(header.length, 10);
      expect(header.magic, 0xFA000000);
      expect(header.version, 0x01);
      expect(header.requestId, 0);
      expect(header.flags.length, 3);
      expect(header.reserved.length, 7);
    });

    test('should round-trip toJson and fromJson', () {
      final header = MessageHeader(
        type: MessageType.authRequest,
        length: 42,
        requestId: 1,
      );

      final json = header.toJson();
      final restored = MessageHeader.fromJson(json);

      expect(restored.type, header.type);
      expect(restored.length, header.length);
      expect(restored.magic, header.magic);
      expect(restored.version, header.version);
      expect(restored.requestId, header.requestId);
    });
  });

  group('Message', () {
    test('should create message with header and payload', () {
      final header = MessageHeader(
        type: MessageType.heartbeat,
        length: 5,
      );
      final payload = <String, dynamic>{'ts': 12345};
      final message = Message(
        header: header,
        payload: payload,
        checksum: 100,
      );

      expect(message.header.type, MessageType.heartbeat);
      expect(message.payload['ts'], 12345);
      expect(message.checksum, 100);
    });

    test('should validate checksum when equal', () {
      final message = Message(
        header: MessageHeader(type: MessageType.error, length: 0),
        payload: {},
        checksum: 0,
      );

      expect(message.validateChecksum(0), isTrue);
      expect(message.validateChecksum(1), isFalse);
    });

    test('should round-trip toJson and fromJson', () {
      final message = Message(
        header: MessageHeader(
          type: MessageType.authResponse,
          length: 2,
        ),
        payload: <String, dynamic>{'success': true},
        checksum: 42,
      );

      final json = message.toJson();
      final restored = Message.fromJson(json);

      expect(restored.header.type, message.header.type);
      expect(restored.payload['success'], true);
      expect(restored.checksum, message.checksum);
    });
  });
}
