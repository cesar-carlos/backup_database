import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/heartbeat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('createHeartbeatMessage', () {
    test('should create message with heartbeat type', () {
      final message = createHeartbeatMessage();

      expect(message.header.type, MessageType.heartbeat);
    });

    test('should have payload with ts', () {
      final message = createHeartbeatMessage();

      expect(message.payload.containsKey('ts'), isTrue);
      expect(message.payload['ts'], isA<int>());
    });
  });

  group('isHeartbeatMessage', () {
    test('should return true for heartbeat message', () {
      final message = createHeartbeatMessage();

      expect(isHeartbeatMessage(message), isTrue);
    });

    test('should return false for non-heartbeat message', () {
      final otherMessage = Message(
        header: MessageHeader(
          type: MessageType.authRequest,
          length: 0,
        ),
        payload: <String, dynamic>{},
        checksum: 0,
      );

      expect(isHeartbeatMessage(otherMessage), isFalse);
    });
  });

  group('HeartbeatManager', () {
    test('should call sendHeartbeat when start and interval elapses', () async {
      Message? sent;
      final manager = HeartbeatManager(
        sendHeartbeat: (m) {
          sent = m;
        },
        onTimeout: () {},
        interval: const Duration(milliseconds: 50),
        timeout: const Duration(seconds: 10),
      );

      manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(sent, isNotNull);
      expect(sent!.header.type, MessageType.heartbeat);
      manager.stop();
    });

    test('should update lastReceived on onHeartbeatReceived', () async {
      var timeoutCalled = false;
      final manager = HeartbeatManager(
        sendHeartbeat: (_) {},
        onTimeout: () {
          timeoutCalled = true;
        },
        interval: const Duration(seconds: 60),
        timeout: const Duration(milliseconds: 50),
      );

      manager.start();
      manager.onHeartbeatReceived();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(timeoutCalled, isFalse);
      manager.stop();
    });

    test('stop should cancel timers', () async {
      var sendCount = 0;
      final manager = HeartbeatManager(
        sendHeartbeat: (_) {
          sendCount++;
        },
        onTimeout: () {},
        interval: const Duration(milliseconds: 30),
        timeout: const Duration(seconds: 10),
      );

      manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final countAfterStart = sendCount;
      manager.stop();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(sendCount, countAfterStart);
    });
  });
}
