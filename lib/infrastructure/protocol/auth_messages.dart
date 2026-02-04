import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

Message createAuthRequest({
  required String serverId,
  required String passwordHash,
}) {
  final payload = <String, dynamic>{
    'serverId': serverId,
    'passwordHash': passwordHash,
    'ts': DateTime.now().millisecondsSinceEpoch,
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.authRequest,
      length: length,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createAuthResponse({required bool success, String? error}) {
  final payload = <String, dynamic>{
    'success': success,
    ...? (error != null ? {'error': error} : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.authResponse,
      length: length,
    ),
    payload: payload,
    checksum: 0,
  );
}

bool isAuthRequestMessage(Message message) =>
    message.header.type == MessageType.authRequest;

bool isAuthResponseMessage(Message message) =>
    message.header.type == MessageType.authResponse;
