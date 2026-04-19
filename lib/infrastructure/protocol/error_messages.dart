import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';

/// Constroi mensagem de erro padronizada (REST-like).
///
/// Quando [errorCode] e fornecido, o `statusCode` e derivado
/// automaticamente da tabela oficial em `StatusCodes.forErrorCode`
/// (parte da entrega F0.5/F0.6/P1.2 do plano). Cliente que ja le
/// `statusCode` pode aplicar retry/backoff sem ter que conhecer o
/// `errorCode`. Cliente legado simplesmente ignora o campo —
/// backward-compat preservada.
///
/// Quando [errorCode] e omitido, `statusCode` cai em `500`
/// (`InternalServerError`) por seguranca — fail-safe que torna obvio
/// no log/teste que falta declarar o `errorCode` apropriado.
///
/// [statusCodeOverride] permite forcar um `statusCode` diferente do
/// derivado (raro — usado quando o handler precisa diferenciar
/// nuances dentro do mesmo `errorCode`, ex.: `409 BACKUP_ALREADY_RUNNING`
/// vs `409 INVALID_STATE_TRANSITION`).
Message createErrorMessage({
  required int requestId,
  required String errorMessage,
  ErrorCode? errorCode,
  int? statusCodeOverride,
}) {
  final statusCode = statusCodeOverride ??
      (errorCode != null
          ? StatusCodes.forErrorCode(errorCode)
          : StatusCodes.internalServerError);

  final payload = <String, dynamic>{
    'error': errorMessage,
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

bool isErrorMessage(Message message) =>
    message.header.type == MessageType.error;

String? getErrorFromMessage(Message message) =>
    message.payload['error'] as String?;

ErrorCode? getErrorCodeFromMessage(Message message) {
  final code = message.payload['errorCode'] as String?;
  return code != null ? ErrorCode.fromString(code) : null;
}

/// Le o `statusCode` HTTP-like do payload da mensagem. Retorna `null`
/// quando o servidor nao envia o campo (servidor `v1` legado).
/// Cliente pode usar `?? StatusCodes.internalServerError` como fallback
/// conservador quando quiser tratar como erro de servidor.
int? getStatusCodeFromMessage(Message message) {
  final raw = message.payload['statusCode'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}
