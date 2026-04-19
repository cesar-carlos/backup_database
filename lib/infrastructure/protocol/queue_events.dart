import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/response_envelope.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';

/// Eventos de fila publicados pelo servidor (PR-3a):
/// `backupQueued`, `backupDequeued`, `backupStarted`.
///
/// Todos carregam:
/// - `runId`: identifica a execucao especifica.
/// - `scheduleId`: identifica o agendamento.
/// - `eventId`: UUID unico do evento — cliente usa para detectar
///   duplicatas apos reconnect (ex.: servidor re-envia eventos por
///   janela de retencao).
/// - `sequence`: monotonico por servidor (incrementado a cada evento
///   publicado). Cliente ordena por `sequence` para garantir consumo
///   na ordem correta mesmo se eventos chegarem fora de ordem por
///   buffer/reconnect.
/// - `serverTimeUtc`: timestamp do evento (UTC ISO-8601).
/// - `message?`: descricao opcional para UI.
///
/// Servidor mantem `sequence` atomico monotonico (in-memory v1;
/// persistido em PR-3 commit 5).

Message createBackupQueuedEvent({
  required String runId,
  required String scheduleId,
  required int sequence,
  required String eventId,
  required DateTime serverTimeUtc,
  int? queuePosition,
  String? requestedBy,
  String? message,
}) =>
    _buildQueueEvent(
      type: MessageType.backupQueued,
      runId: runId,
      scheduleId: scheduleId,
      sequence: sequence,
      eventId: eventId,
      serverTimeUtc: serverTimeUtc,
      extra: <String, dynamic>{
        'queuePosition': ?queuePosition,
        'requestedBy': ?requestedBy,
      },
      message: message,
    );

Message createBackupDequeuedEvent({
  required String runId,
  required String scheduleId,
  required int sequence,
  required String eventId,
  required DateTime serverTimeUtc,
  String? reason, // 'dispatched' (vai virar `backupStarted`) ou 'cancelled'
  String? message,
}) =>
    _buildQueueEvent(
      type: MessageType.backupDequeued,
      runId: runId,
      scheduleId: scheduleId,
      sequence: sequence,
      eventId: eventId,
      serverTimeUtc: serverTimeUtc,
      extra: <String, dynamic>{
        'reason': ?reason,
      },
      message: message,
    );

Message createBackupStartedEvent({
  required String runId,
  required String scheduleId,
  required int sequence,
  required String eventId,
  required DateTime serverTimeUtc,
  String? message,
}) =>
    _buildQueueEvent(
      type: MessageType.backupStarted,
      runId: runId,
      scheduleId: scheduleId,
      sequence: sequence,
      eventId: eventId,
      serverTimeUtc: serverTimeUtc,
      message: message,
    );

Message _buildQueueEvent({
  required MessageType type,
  required String runId,
  required String scheduleId,
  required int sequence,
  required String eventId,
  required DateTime serverTimeUtc,
  Map<String, dynamic> extra = const <String, dynamic>{},
  String? message,
}) {
  final base = <String, dynamic>{
    'runId': runId,
    'scheduleId': scheduleId,
    'eventId': eventId,
    'sequence': sequence,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
    'message': ?message,
    ...extra,
  };
  final payload = wrapSuccessResponse(base);
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

/// Snapshot tipado de qualquer evento de fila — cliente usa para
/// reordenar e deduplicar.
class QueueEvent {
  const QueueEvent({
    required this.type,
    required this.runId,
    required this.scheduleId,
    required this.eventId,
    required this.sequence,
    required this.serverTimeUtc,
    this.queuePosition,
    this.reason,
    this.requestedBy,
    this.message,
  });

  final MessageType type;
  final String runId;
  final String scheduleId;
  final String eventId;
  final int sequence;
  final DateTime serverTimeUtc;
  final int? queuePosition;
  final String? reason;
  final String? requestedBy;
  final String? message;

  bool get isQueued => type == MessageType.backupQueued;
  bool get isDequeued => type == MessageType.backupDequeued;
  bool get isStarted => type == MessageType.backupStarted;
}

QueueEvent? readQueueEvent(Message message) {
  final t = message.header.type;
  if (t != MessageType.backupQueued &&
      t != MessageType.backupDequeued &&
      t != MessageType.backupStarted) {
    return null;
  }
  final p = message.payload;
  return QueueEvent(
    type: t,
    runId: p['runId'] is String ? p['runId'] as String : '',
    scheduleId: p['scheduleId'] is String ? p['scheduleId'] as String : '',
    eventId: p['eventId'] is String ? p['eventId'] as String : '',
    sequence: p['sequence'] is int ? p['sequence'] as int : 0,
    serverTimeUtc: p['serverTimeUtc'] is String
        ? (DateTime.tryParse(p['serverTimeUtc'] as String) ??
            DateTime.fromMillisecondsSinceEpoch(0).toUtc())
        : DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
    queuePosition: p['queuePosition'] is int ? p['queuePosition'] as int : null,
    reason: p['reason'] is String ? p['reason'] as String : null,
    requestedBy: p['requestedBy'] is String ? p['requestedBy'] as String : null,
    message: p['message'] is String ? p['message'] as String : null,
  );
}

// ---------------------------------------------------------------------------
// cancelQueuedBackup
// ---------------------------------------------------------------------------

/// `cancelQueuedBackup`: cancela execucao que ainda esta na fila.
/// Diferente de `cancelBackup` (que cancela execucao em curso).
Message createCancelQueuedBackupRequest({
  required String runId,
  String? idempotencyKey,
  int requestId = 0,
}) {
  if (runId.isEmpty) {
    throw ArgumentError('cancelQueuedBackup: runId obrigatorio');
  }
  final payload = <String, dynamic>{
    'runId': runId,
    'idempotencyKey': ?((idempotencyKey?.isNotEmpty ?? false)
        ? idempotencyKey
        : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.cancelQueuedBackupRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Resposta de `cancelQueuedBackup`. Sucesso = state=cancelled;
/// runId nao esta na fila = state=notFound + 409 NO_ACTIVE_EXECUTION.
Message createCancelQueuedBackupResponse({
  required int requestId,
  required ExecutionState state,
  required String runId,
  required DateTime serverTimeUtc,
  String? scheduleId,
  String? message,
  ErrorCode? errorCode,
}) {
  final base = <String, dynamic>{
    'state': state.name,
    'runId': runId,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
    'scheduleId': ?scheduleId,
    'message': ?message,
    'errorCode': ?errorCode?.code,
  };
  final statusCode = errorCode != null
      ? StatusCodes.forErrorCode(errorCode)
      : StatusCodes.ok;
  final payload = wrapSuccessResponse(base, statusCode: statusCode);
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.cancelQueuedBackupResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

class CancelQueuedBackupResult {
  const CancelQueuedBackupResult({
    required this.state,
    required this.runId,
    required this.serverTimeUtc,
    this.scheduleId,
    this.message,
    this.errorCode,
  });

  final ExecutionState state;
  final String runId;
  final DateTime serverTimeUtc;
  final String? scheduleId;
  final String? message;
  final ErrorCode? errorCode;

  bool get isCancelled => state == ExecutionState.cancelled;
  bool get isNotFound => state == ExecutionState.notFound;
}

CancelQueuedBackupResult readCancelQueuedBackupResponse(Message message) {
  final p = message.payload;
  final stateRaw = p['state'] is String ? p['state'] as String : '';
  final state = ExecutionState.values.firstWhere(
    (e) => e.name == stateRaw,
    orElse: () => ExecutionState.unknown,
  );
  final runId = p['runId'] is String ? p['runId'] as String : '';
  final serverTime = p['serverTimeUtc'] is String
      ? (DateTime.tryParse(p['serverTimeUtc'] as String) ??
          DateTime.fromMillisecondsSinceEpoch(0).toUtc())
      : DateTime.fromMillisecondsSinceEpoch(0).toUtc();
  final scheduleId = p['scheduleId'] is String ? p['scheduleId'] as String : null;
  final messageText = p['message'] is String ? p['message'] as String : null;
  final errorCodeRaw = p['errorCode'] is String ? p['errorCode'] as String : null;
  final errorCode = errorCodeRaw != null ? ErrorCode.fromString(errorCodeRaw) : null;
  return CancelQueuedBackupResult(
    state: state,
    runId: runId,
    serverTimeUtc: serverTime,
    scheduleId: scheduleId,
    message: messageText,
    errorCode: errorCode,
  );
}
