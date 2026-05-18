import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_policy.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:flutter_test/flutter_test.dart';

Message _message(MessageType type, {String? idempotencyKey}) => Message(
  header: MessageHeader(type: type, length: 0, requestId: 42),
  payload: idempotencyKey == null
      ? <String, dynamic>{}
      : <String, dynamic>{'idempotencyKey': idempotencyKey},
  checksum: 0,
);

void main() {
  group('IdempotencyPolicy', () {
    test('startBackup requires idempotencyKey', () {
      expect(
        IdempotencyPolicy.isKeyRequired(MessageType.startBackupRequest),
        isTrue,
      );
      final error = IdempotencyPolicy.missingKeyErrorMessage(
        message: _message(MessageType.startBackupRequest),
        operationType: MessageType.startBackupRequest,
      );
      expect(error, isNotNull);
      expect(error!.payload['errorCode'], ErrorCode.invalidRequest.code);
    });

    test('listSchedules does not require idempotencyKey', () {
      expect(
        IdempotencyPolicy.missingKeyErrorMessage(
          message: _message(MessageType.listSchedules),
          operationType: MessageType.listSchedules,
        ),
        isNull,
      );
    });

    test('pauseSchedule does not require idempotencyKey', () {
      expect(
        IdempotencyPolicy.missingKeyErrorMessage(
          message: _message(MessageType.pauseSchedule),
          operationType: MessageType.pauseSchedule,
        ),
        isNull,
      );
    });

    test('valid key returns null error', () {
      expect(
        IdempotencyPolicy.missingKeyErrorMessage(
          message: _message(
            MessageType.createSchedule,
            idempotencyKey: 'uuid-1',
          ),
          operationType: MessageType.createSchedule,
        ),
        isNull,
      );
    });
  });
}
