import 'dart:convert';

import 'package:backup_database/core/security/auth_challenge.dart';
import 'package:backup_database/core/security/password_hasher.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

Message createAuthRequest({
  required String serverId,
  required String passwordHash,
  String? nonce,
}) {
  final payload = <String, dynamic>{
    'serverId': serverId,
    'passwordHash': passwordHash,
    'ts': DateTime.now().millisecondsSinceEpoch,
    'nonce': ?nonce,
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

Message createAuthResponse({
  required bool success,
  String? error,
  ErrorCode? errorCode,
}) {
  final payload = <String, dynamic>{
    'success': success,
    ...?(error != null ? {'error': error} : null),
    ...?(errorCode != null ? {'errorCode': errorCode.code} : null),
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

Message createAuthChallengeRequest({required String serverId}) {
  return _authMessage(
    type: MessageType.authChallenge,
    payload: <String, dynamic>{'serverId': serverId},
  );
}

Message createAuthChallenge({required String nonce}) {
  return _authMessage(
    type: MessageType.authChallenge,
    payload: <String, dynamic>{'nonce': nonce},
  );
}

bool isAuthChallengeMessage(Message message) =>
    message.header.type == MessageType.authChallenge;

bool isAuthChallengeRequest(Message message) {
  if (!isAuthChallengeMessage(message)) {
    return false;
  }
  final serverId = message.payload['serverId'];
  return serverId is String && serverId.isNotEmpty;
}

String? getAuthChallengeNonce(Message message) {
  final nonce = message.payload['nonce'];
  if (nonce is! String || nonce.isEmpty) {
    return null;
  }
  return nonce;
}

String? getAuthRequestNonce(Message message) => getAuthChallengeNonce(message);

Message? createChallengeAuthRequest({
  required Message challenge,
  required String serverId,
  required String password,
}) {
  if (!isAuthChallengeMessage(challenge)) {
    return null;
  }
  final nonce = getAuthChallengeNonce(challenge);
  if (nonce == null) {
    return null;
  }
  final passwordHash = PasswordHasher.hash(password, serverId);
  return createAuthRequest(
    serverId: serverId,
    passwordHash: AuthChallenge.responseFor(
      nonce: nonce,
      passwordHash: passwordHash,
    ),
    nonce: nonce,
  );
}

Message _authMessage({
  required MessageType type,
  required Map<String, dynamic> payload,
}) {
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: type,
      length: length,
    ),
    payload: payload,
    checksum: 0,
  );
}

String? getAuthErrorMessage(Message message) =>
    message.payload['error'] as String?;

ErrorCode? getAuthErrorCode(Message message) {
  final code = message.payload['errorCode'] as String?;
  if (code == null || code.isEmpty) {
    return null;
  }
  return ErrorCode.fromString(code);
}
