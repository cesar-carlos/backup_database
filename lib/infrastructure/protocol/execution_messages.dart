import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/response_envelope.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';

/// `startBackup` (M2.2/PR-2). Cliente solicita execucao de um backup
/// agendado. Servidor responde IMEDIATAMENTE com `runId` + `state`,
/// sem aguardar conclusao. Eventos `backupProgress/Complete/Failed`
/// chegam separados via stream com o mesmo `runId`.
///
/// `idempotencyKey` opcional protege contra retransmissao por
/// reconexao. Quando informada, servidor consulta `IdempotencyRegistry`
/// e retorna a MESMA resposta cacheada se a chave ja foi vista dentro
/// do TTL.
Message createStartBackupRequest({
  required String scheduleId,
  String? idempotencyKey,
  bool queueIfBusy = false,
  int requestId = 0,
}) {
  if (scheduleId.isEmpty) {
    throw ArgumentError('startBackup: scheduleId obrigatorio');
  }
  final payload = <String, dynamic>{
    'scheduleId': scheduleId,
    ...?(idempotencyKey != null && idempotencyKey.isNotEmpty
        ? {'idempotencyKey': idempotencyKey}
        : null),
    // Cliente que aceita ser enfileirado quando ja ha backup em
    // execucao envia true. Disparo manual padrao envia false (recebe
    // 409 BACKUP_ALREADY_RUNNING). Default=false preserva comportamento
    // legado da fase PR-2.
    if (queueIfBusy) 'queueIfBusy': true,
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.startBackupRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Resposta de `startBackup`. Sucesso retorna `state = running` (ou
/// `queued` quando PR-3b implementar fila) com `runId` valido. Em
/// resposta de aceite, `statusCode = 202 Accepted` (semantica REST
/// para "request aceita, processamento async em curso").
///
/// Falha retorna `success: true` mas com `connected:false`-equivalente:
/// state = `failed` ou `notFound`, `error`/`errorCode` preenchidos. Se
/// houver falha de transporte/protocolo, o servidor envia
/// `MessageType.error` ao inves desta resposta.
Message createStartBackupResponse({
  required int requestId,
  required String runId,
  required ExecutionState state,
  required String scheduleId,
  required DateTime serverTimeUtc,
  int? queuePosition,
  String? message,
}) {
  final base = <String, dynamic>{
    'runId': runId,
    'state': state.name,
    'scheduleId': scheduleId,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
    ...?(queuePosition != null ? {'queuePosition': queuePosition} : null),
    ...?(message != null ? {'message': message} : null),
  };

  // Aceite assincrono -> 202. Outros estados podem indicar resposta
  // sincrona (ex.: cliente reusou idempotencyKey de execucao ja
  // concluida -> state pode vir `completed` direto com 200).
  final statusCode = state == ExecutionState.running ||
          state == ExecutionState.queued
      ? StatusCodes.accepted
      : StatusCodes.ok;

  final payload = wrapSuccessResponse(base, statusCode: statusCode);
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.startBackupResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Snapshot tipado da resposta de `startBackup`.
class StartBackupResult {
  const StartBackupResult({
    required this.runId,
    required this.state,
    required this.scheduleId,
    required this.serverTimeUtc,
    this.queuePosition,
    this.message,
  });

  final String runId;
  final ExecutionState state;
  final String scheduleId;
  final DateTime serverTimeUtc;
  final int? queuePosition;
  final String? message;

  bool get isAccepted =>
      state == ExecutionState.running || state == ExecutionState.queued;
  bool get isRunning => state == ExecutionState.running;
  bool get isQueued => state == ExecutionState.queued;
}

StartBackupResult readStartBackupResponse(Message message) {
  final p = message.payload;
  final runId = p['runId'] is String ? p['runId'] as String : '';
  final stateRaw = p['state'] is String ? p['state'] as String : '';
  final state = ExecutionState.values.firstWhere(
    (e) => e.name == stateRaw,
    orElse: () => ExecutionState.unknown,
  );
  final scheduleId = p['scheduleId'] is String ? p['scheduleId'] as String : '';
  final serverTimeRaw = p['serverTimeUtc'];
  final serverTime = serverTimeRaw is String
      ? (DateTime.tryParse(serverTimeRaw) ??
          DateTime.fromMillisecondsSinceEpoch(0).toUtc())
      : DateTime.fromMillisecondsSinceEpoch(0).toUtc();
  final queuePosition = p['queuePosition'] is int ? p['queuePosition'] as int : null;
  final messageText = p['message'] is String ? p['message'] as String : null;

  return StartBackupResult(
    runId: runId,
    state: state,
    scheduleId: scheduleId,
    serverTimeUtc: serverTime,
    queuePosition: queuePosition,
    message: messageText,
  );
}

/// `cancelBackup`. Cliente envia `runId` ou `scheduleId` (XOR — runId
/// e preferido em v2; scheduleId aceito para compat com clientes que
/// nao memorizam runId).
Message createCancelBackupRequest({
  String? runId,
  String? scheduleId,
  String? idempotencyKey,
  int requestId = 0,
}) {
  final hasRun = runId != null && runId.isNotEmpty;
  final hasSch = scheduleId != null && scheduleId.isNotEmpty;
  if (hasRun == hasSch) {
    throw ArgumentError(
      'cancelBackup: informe APENAS um de `runId` ou `scheduleId` (XOR)',
    );
  }
  final payload = <String, dynamic>{
    if (hasRun) 'runId': runId,
    if (hasSch) 'scheduleId': scheduleId,
    ...?(idempotencyKey != null && idempotencyKey.isNotEmpty
        ? {'idempotencyKey': idempotencyKey}
        : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.cancelBackupRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Resposta de `cancelBackup`. `state = cancelled` quando aceite,
/// `noActiveExecution` quando nao havia execucao ativa, `failed`
/// para erro inesperado.
Message createCancelBackupResponse({
  required int requestId,
  required ExecutionState state,
  required DateTime serverTimeUtc,
  String? runId,
  String? scheduleId,
  String? message,
  ErrorCode? errorCode,
}) {
  final base = <String, dynamic>{
    'state': state.name,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
    ...?(runId != null ? {'runId': runId} : null),
    ...?(scheduleId != null ? {'scheduleId': scheduleId} : null),
    ...?(message != null ? {'message': message} : null),
    ...?(errorCode != null ? {'errorCode': errorCode.code} : null),
  };

  final statusCode = errorCode != null
      ? StatusCodes.forErrorCode(errorCode)
      : StatusCodes.ok;

  final payload = wrapSuccessResponse(base, statusCode: statusCode);
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.cancelBackupResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Snapshot tipado da resposta de `cancelBackup`.
class CancelBackupResult {
  const CancelBackupResult({
    required this.state,
    required this.serverTimeUtc,
    this.runId,
    this.scheduleId,
    this.message,
    this.errorCode,
  });

  final ExecutionState state;
  final DateTime serverTimeUtc;
  final String? runId;
  final String? scheduleId;
  final String? message;
  final ErrorCode? errorCode;

  bool get isCancelled => state == ExecutionState.cancelled;
  bool get hasNoActiveExecution => errorCode == ErrorCode.noActiveExecution;
}

CancelBackupResult readCancelBackupResponse(Message message) {
  final p = message.payload;
  final stateRaw = p['state'] is String ? p['state'] as String : '';
  final state = ExecutionState.values.firstWhere(
    (e) => e.name == stateRaw,
    orElse: () => ExecutionState.unknown,
  );
  final serverTimeRaw = p['serverTimeUtc'];
  final serverTime = serverTimeRaw is String
      ? (DateTime.tryParse(serverTimeRaw) ??
          DateTime.fromMillisecondsSinceEpoch(0).toUtc())
      : DateTime.fromMillisecondsSinceEpoch(0).toUtc();
  final runId = p['runId'] is String ? p['runId'] as String : null;
  final scheduleId = p['scheduleId'] is String ? p['scheduleId'] as String : null;
  final messageText = p['message'] is String ? p['message'] as String : null;
  final errorCodeRaw = p['errorCode'] is String ? p['errorCode'] as String : null;
  final errorCode = errorCodeRaw != null ? ErrorCode.fromString(errorCodeRaw) : null;

  return CancelBackupResult(
    state: state,
    serverTimeUtc: serverTime,
    runId: runId,
    scheduleId: scheduleId,
    message: messageText,
    errorCode: errorCode,
  );
}
