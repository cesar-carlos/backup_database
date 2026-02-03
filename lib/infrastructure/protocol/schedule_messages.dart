import 'dart:convert';

import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/schedule_serialization.dart';

Message createListSchedulesMessage({int requestId = 0}) {
  const payload = <String, dynamic>{};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.listSchedules,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createScheduleListMessage({
  required int requestId,
  required List<Schedule> schedules,
}) {
  final payload = <String, dynamic>{
    'schedules': schedules.map(scheduleToMap).toList(),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.scheduleList,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createUpdateScheduleMessage({
  required int requestId,
  required Schedule schedule,
}) {
  final payload = scheduleToMap(schedule);
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.updateSchedule,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createScheduleUpdatedMessage({
  required int requestId,
  required Schedule schedule,
}) {
  final payload = scheduleToMap(schedule);
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.scheduleUpdated,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createExecuteScheduleMessage({
  required int requestId,
  required String scheduleId,
}) {
  final payload = <String, dynamic>{'scheduleId': scheduleId};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.executeSchedule,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createScheduleErrorMessage({
  required int requestId,
  required String error,
}) {
  final payload = <String, dynamic>{'error': error};
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

List<Schedule> getSchedulesFromListPayload(Message message) {
  final list = message.payload['schedules'] as List<dynamic>?;
  if (list == null) return [];
  return list
      .map((e) => scheduleFromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
}

Schedule getScheduleFromUpdatePayload(Message message) {
  return scheduleFromMap(message.payload);
}

String getScheduleIdFromExecutePayload(Message message) {
  return message.payload['scheduleId'] as String? ?? '';
}

String? getErrorFromPayload(Message message) {
  return message.payload['error'] as String?;
}

bool isListSchedulesMessage(Message message) =>
    message.header.type == MessageType.listSchedules;

bool isScheduleListMessage(Message message) =>
    message.header.type == MessageType.scheduleList;

bool isUpdateScheduleMessage(Message message) =>
    message.header.type == MessageType.updateSchedule;

bool isScheduleUpdatedMessage(Message message) =>
    message.header.type == MessageType.scheduleUpdated;

bool isExecuteScheduleMessage(Message message) =>
    message.header.type == MessageType.executeSchedule;

Message createBackupProgressMessage({
  required int requestId,
  required String scheduleId,
  required String step,
  required String message,
  double progress = 0.0,
}) {
  final payload = <String, dynamic>{
    'scheduleId': scheduleId,
    'step': step,
    'message': message,
    'progress': progress,
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.backupProgress,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createBackupCompleteMessage({
  required int requestId,
  required String scheduleId,
  String? message,
  String? backupPath,
}) {
  final payload = <String, dynamic>{
    'scheduleId': scheduleId,
    'message': message ?? 'Backup concluído',
    ...?(backupPath != null ? {'backupPath': backupPath} : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.backupComplete,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createBackupFailedMessage({
  required int requestId,
  required String scheduleId,
  required String error,
}) {
  final payload = <String, dynamic>{
    'scheduleId': scheduleId,
    'error': error,
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.backupFailed,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

String? getScheduleIdFromBackupMessage(Message message) {
  return message.payload['scheduleId'] as String?;
}

String? getBackupPathFromBackupComplete(Message message) {
  return message.payload['backupPath'] as String?;
}

String? getStepFromBackupProgress(Message message) {
  return message.payload['step'] as String?;
}

String? getMessageFromBackupProgress(Message message) {
  return message.payload['message'] as String?;
}

double? getProgressFromBackupProgress(Message message) {
  return message.payload['progress'] as double?;
}

String? getErrorFromBackupFailed(Message message) {
  return message.payload['error'] as String?;
}

bool isBackupProgressMessage(Message message) =>
    message.header.type == MessageType.backupProgress;

bool isBackupCompleteMessage(Message message) =>
    message.header.type == MessageType.backupComplete;

bool isBackupFailedMessage(Message message) =>
    message.header.type == MessageType.backupFailed;
