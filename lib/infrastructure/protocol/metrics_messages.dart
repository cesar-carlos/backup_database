import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

Message createMetricsRequestMessage({int requestId = 0}) {
  const payload = <String, dynamic>{};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.metricsRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createMetricsResponseMessage({
  required int requestId,
  required Map<String, dynamic> payload,
}) {
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.metricsResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

bool isMetricsRequestMessage(Message message) =>
    message.header.type == MessageType.metricsRequest;

bool isMetricsResponseMessage(Message message) =>
    message.header.type == MessageType.metricsResponse;

Map<String, dynamic> getMetricsFromPayload(Message message) =>
    Map<String, dynamic>.from(message.payload);
