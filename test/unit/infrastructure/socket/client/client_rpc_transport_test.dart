import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/client/client_rpc_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClientRpcTransport', () {
    test('should start request ids at 1', () {
      final transport = ClientRpcTransport();

      expect(transport.allocateRequestId(), 1);
      expect(transport.allocateRequestId(), 2);
    });

    test('should ignore an unbound protocol error with requestId 0', () {
      final transport = ClientRpcTransport();
      final requestId = transport.allocateRequestId();
      final pending = transport.register(requestId);

      transport.completeIfPending(
        0,
        createErrorMessage(
          requestId: 0,
          errorMessage: 'Failed to parse message',
        ),
      );

      expect(pending.isCompleted, isFalse);
      expect(transport.pendingCount, 1);
    });

    test(
      'should complete the pending rpc when the error names that request',
      () {
        final transport = ClientRpcTransport();
        final requestId = transport.allocateRequestId();
        final pending = transport.register(requestId);
        final error = createErrorMessage(
          requestId: requestId,
          errorMessage: 'falhou',
        );

        transport.completeIfPending(requestId, error);

        expect(pending.isCompleted, isTrue);
        expect(pending.future, completion(error));
      },
    );

    test('should still complete a non-error response for its request id', () {
      final transport = ClientRpcTransport();
      final requestId = transport.allocateRequestId();
      final pending = transport.register(requestId);
      final message = Message(
        header: MessageHeader(
          type: MessageType.scheduleList,
          length: 0,
          requestId: requestId,
        ),
        payload: const <String, dynamic>{},
        checksum: 0,
      );

      transport.completeIfPending(requestId, message);

      expect(pending.isCompleted, isTrue);
    });
  });
}
