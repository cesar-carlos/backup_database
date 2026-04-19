import 'dart:convert';

import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/schedule_serialization.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';

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

/// Constroi mensagem de erro de schedule com envelope REST-like.
///
/// Quando [errorCode] e fornecido, `statusCode` e derivado
/// automaticamente da tabela oficial em `StatusCodes.forErrorCode` e
/// `errorCode` e emitido no payload — fechando F0.2 do plano. Cliente
/// pode tratar `BACKUP_ALREADY_RUNNING` como `409` retryable apos
/// backoff, `NOT_AUTHENTICATED` como `401`, etc.
///
/// Quando [errorCode] e omitido, mantem comportamento legado (apenas
/// `error` como string + `statusCode = 500` fail-safe). Migracao
/// gradual nao quebra clientes que ja consomem a forma antiga.
Message createScheduleErrorMessage({
  required int requestId,
  required String error,
  ErrorCode? errorCode,
  int? statusCodeOverride,
}) {
  final statusCode = statusCodeOverride ??
      (errorCode != null
          ? StatusCodes.forErrorCode(errorCode)
          : StatusCodes.internalServerError);

  final payload = <String, dynamic>{
    'error': error,
    'statusCode': statusCode,
    ...?(errorCode != null ? {'errorCode': errorCode.code} : null),
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

/// `runId` e opcional para preservar compatibilidade com clientes `v1`
/// que ignoram o campo. Servidor `v2+` passa a popular sempre, viabilizando
/// correlacao end-to-end por execucao (ver M2.3 do plano e
/// `RemoteExecutionRegistry`).
Message createBackupProgressMessage({
  required int requestId,
  required String scheduleId,
  required String step,
  required String message,
  double progress = 0.0,
  String? runId,
}) {
  final payload = <String, dynamic>{
    'scheduleId': scheduleId,
    'step': step,
    'message': message,
    'progress': progress,
    ...?(runId != null ? {'runId': runId} : null),
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
  String? runId,
}) {
  final payload = <String, dynamic>{
    'scheduleId': scheduleId,
    'message': message ?? 'Backup concluído',
    ...?(backupPath != null ? {'backupPath': backupPath} : null),
    ...?(runId != null ? {'runId': runId} : null),
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
  String? runId,
}) {
  final payload = <String, dynamic>{
    'scheduleId': scheduleId,
    'error': error,
    ...?(runId != null ? {'runId': runId} : null),
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

/// Extrai o `runId` quando presente no payload de backup
/// (`backupProgress`, `backupComplete`, `backupFailed`). Retorna `null`
/// quando o servidor e anterior a M2.3 (`v1`) ou quando o cliente
/// processa mensagens legadas, garantindo backward compat.
String? getRunIdFromBackupMessage(Message message) {
  return message.payload['runId'] as String?;
}

bool isBackupProgressMessage(Message message) =>
    message.header.type == MessageType.backupProgress;

bool isBackupCompleteMessage(Message message) =>
    message.header.type == MessageType.backupComplete;

bool isBackupFailedMessage(Message message) =>
    message.header.type == MessageType.backupFailed;

// ============================================================================
// CANCEL SCHEDULE
// ============================================================================

Message createCancelScheduleMessage({
  required int requestId,
  required String scheduleId,
}) {
  final payload = <String, dynamic>{
    'scheduleId': scheduleId,
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.cancelSchedule,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createScheduleCancelledMessage({
  required int requestId,
  required String scheduleId,
}) {
  final payload = <String, dynamic>{
    'scheduleId': scheduleId,
    'message': 'Backup cancelado pelo usuário',
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.scheduleCancelled,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

String? getScheduleIdFromCancelRequest(Message message) {
  return message.payload['scheduleId'] as String?;
}

bool isCancelScheduleMessage(Message message) =>
    message.header.type == MessageType.cancelSchedule;

bool isScheduleCancelledMessage(Message message) =>
    message.header.type == MessageType.scheduleCancelled;
