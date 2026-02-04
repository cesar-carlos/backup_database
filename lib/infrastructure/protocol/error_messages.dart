import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

Message createErrorMessage({
  required int requestId,
  required String errorMessage,
  ErrorCode? errorCode,
}) {
  final payload = <String, dynamic>{
    'error': errorMessage,
    ...? (errorCode != null ? {'errorCode': errorCode.code} : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.error,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

bool isErrorMessage(Message message) =>
    message.header.type == MessageType.error;

String? getErrorFromMessage(Message message) =>
    message.payload['error'] as String?;

ErrorCode? getErrorCodeFromMessage(Message message) {
  final code = message.payload['errorCode'] as String?;
  return code != null ? ErrorCode.fromString(code) : null;
}
