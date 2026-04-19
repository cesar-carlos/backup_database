import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/response_envelope.dart';

/// Estado de uma execucao remota consultada por `getExecutionStatus(runId)`.
///
/// Conjunto inicial reflete o que o `RemoteExecutionRegistry` (M2.1)
/// consegue observar hoje. Quando a fila persistida for adicionada
/// (PR-3b), valores como `queued`/`completed`/`failed`/`cancelled`
/// passarao a ser populados pelo servidor a partir de
/// `remote_executions` table; o cliente ja prepara o switch defensivo
/// para tratar todos os casos.
///
/// `running`: execucao em andamento, contexto ativo no registry.
/// `notFound`: `runId` desconhecido — ja terminou (e foi limpo) ou
///   nunca existiu. Cliente pode tentar baixar artefato (se aplicavel)
///   ou disparar nova execucao.
/// `queued`: aguardando slot livre na fila (PR-3b).
/// `completed`: execucao finalizou com sucesso (PR-3c).
/// `failed`: execucao falhou (PR-3c).
/// `cancelled`: execucao foi cancelada (PR-3c).
/// `unknown`: estado indeterminado — fail-closed para casos onde
///   payload e malformado ou servidor reporta valor desconhecido.
enum ExecutionState {
  running,
  notFound,
  queued,
  completed,
  failed,
  cancelled,
  unknown;

  static ExecutionState fromString(String value) {
    return values.firstWhere(
      (s) => s.name == value,
      orElse: () => ExecutionState.unknown,
    );
  }

  /// Cliente pode usar como sinal "tem algo acontecendo agora".
  bool get isActive =>
      this == ExecutionState.running || this == ExecutionState.queued;

  /// Cliente pode usar como sinal "execucao terminou (com sucesso ou nao)".
  bool get isTerminal =>
      this == ExecutionState.completed ||
      this == ExecutionState.failed ||
      this == ExecutionState.cancelled;
}

/// Constroi um `executionStatusRequest` (cliente -> servidor).
///
/// Cliente passa o `runId` (gerado pelo servidor e recebido em
/// `backupProgress`/`Complete`/`Failed` desde M2.3) para reidratar o
/// status apos reconexao ou para polling de progresso.
Message createExecutionStatusRequestMessage({
  required int requestId,
  required String runId,
}) {
  final payload = <String, dynamic>{'runId': runId};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.executionStatusRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Constroi um `executionStatusResponse` (servidor -> cliente).
///
/// [runId] eco do request para correlacao.
/// [state] estado atual ([ExecutionState]).
/// [scheduleId] schedule associado quando conhecido (`null` para
///   `notFound`).
/// [clientId] cliente que originou a execucao quando conhecido.
/// [startedAt] quando o registry registrou o contexto (`null` para
///   `notFound`).
/// [serverTimeUtc] sempre presente para drift de relogio.
/// [queuedPosition] posicao na fila quando `queued` (PR-3b);
///   `null` em outros estados.
Message createExecutionStatusResponseMessage({
  required int requestId,
  required String runId,
  required ExecutionState state,
  required DateTime serverTimeUtc,
  String? scheduleId,
  String? clientId,
  DateTime? startedAt,
  int? queuedPosition,
  String? message,
}) {
  final payload = wrapSuccessResponse(<String, dynamic>{
    'runId': runId,
    'state': state.name,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
    ...?(scheduleId != null ? {'scheduleId': scheduleId} : null),
    ...?(clientId != null ? {'clientId': clientId} : null),
    ...?(startedAt != null
        ? {'startedAt': startedAt.toUtc().toIso8601String()}
        : null),
    ...?(queuedPosition != null ? {'queuedPosition': queuedPosition} : null),
    ...?(message != null ? {'message': message} : null),
  });
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.executionStatusResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

bool isExecutionStatusRequestMessage(Message message) =>
    message.header.type == MessageType.executionStatusRequest;

bool isExecutionStatusResponseMessage(Message message) =>
    message.header.type == MessageType.executionStatusResponse;

/// Le o `runId` de um `executionStatusRequest`.
String? getRunIdFromExecutionStatusRequest(Message message) =>
    message.payload['runId'] as String?;

/// Snapshot tipado do status de uma execucao remota (lado cliente).
class ExecutionStatusResult {
  const ExecutionStatusResult({
    required this.runId,
    required this.state,
    required this.serverTimeUtc,
    this.scheduleId,
    this.clientId,
    this.startedAt,
    this.queuedPosition,
    this.message,
  });

  final String runId;
  final ExecutionState state;
  final DateTime serverTimeUtc;
  final String? scheduleId;
  final String? clientId;
  final DateTime? startedAt;
  final int? queuedPosition;
  final String? message;

  bool get isActive => state.isActive;
  bool get isTerminal => state.isTerminal;
  bool get isNotFound => state == ExecutionState.notFound;
}

/// Le o payload de `executionStatusResponse` em snapshot tipado.
///
/// Defensivo: state desconhecido vira [ExecutionState.unknown] (nao
/// `notFound`, para nao confundir "nao implementado" com "nao existe").
ExecutionStatusResult readExecutionStatusFromResponse(Message message) {
  final payload = message.payload;
  return ExecutionStatusResult(
    runId: (payload['runId'] as String?) ?? '',
    state: ExecutionState.fromString(
      payload['state'] as String? ?? 'unknown',
    ),
    serverTimeUtc: _parseDate(payload['serverTimeUtc']),
    scheduleId: payload['scheduleId'] as String?,
    clientId: payload['clientId'] as String?,
    startedAt: _parseOptionalDate(payload['startedAt']),
    queuedPosition: (payload['queuedPosition'] as num?)?.toInt(),
    message: payload['message'] as String?,
  );
}

DateTime _parseDate(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.now().toUtc();
}

DateTime? _parseOptionalDate(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw)?.toUtc();
  }
  return null;
}
