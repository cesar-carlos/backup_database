import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/response_envelope.dart';

/// Constroi um `sessionRequest` (cliente -> servidor) sem payload.
///
/// O servidor responde com `sessionResponse` informando a sessao do
/// cliente conforme percebida pelo servidor (clientId, serverId,
/// connectedAt, isAuthenticated, peer host:port).
///
/// Uso tipico:
/// - cliente confirma sua identidade percebida pelo servidor (debug).
/// - suporte recebe `clientId` / `serverId` para correlacionar com logs.
/// - cliente pode detectar reconexao (clientId mudou apos reconnect).
///
/// Implementa parte de M1.10 do plano + endpoint complementar do
/// PR-1 ao trio capabilities/health/session.
Message createSessionRequestMessage({int requestId = 0}) {
  const payload = <String, dynamic>{};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.sessionRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Constroi um `sessionResponse` (servidor -> cliente).
///
/// Campos:
/// - [clientId]: id atribuido pelo servidor a esta conexao
///   (`UUID`, gerado em `ClientHandler` no `_onConnection`).
/// - [serverId]: id do servidor que o cliente declarou no auth
///   (`null` se nao autenticado ou se servidor opera sem auth).
/// - [isAuthenticated]: `true` quando handshake passou.
/// - [host], [port]: endereco remoto do peer percebido pelo servidor.
/// - [connectedAt]: quando o `ClientHandler` foi criado.
/// - [serverTimeUtc]: util para detectar drift de relogio.
Message createSessionResponseMessage({
  required int requestId,
  required String clientId,
  required bool isAuthenticated,
  required String host,
  required int port,
  required DateTime connectedAt,
  required DateTime serverTimeUtc,
  String? serverId,
}) {
  final payload = wrapSuccessResponse(<String, dynamic>{
    'clientId': clientId,
    'isAuthenticated': isAuthenticated,
    'host': host,
    'port': port,
    'connectedAt': connectedAt.toUtc().toIso8601String(),
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
    ...?(serverId != null && serverId.isNotEmpty
        ? {'serverId': serverId}
        : null),
  });
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.sessionResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

bool isSessionRequestMessage(Message message) =>
    message.header.type == MessageType.sessionRequest;

bool isSessionResponseMessage(Message message) =>
    message.header.type == MessageType.sessionResponse;

/// Snapshot tipado da sessao do cliente conforme o servidor.
///
/// Util para cliente exibir info de diagnostico, correlacionar com
/// logs de suporte e detectar mudanca de identidade apos reconexao.
class ServerSession {
  const ServerSession({
    required this.clientId,
    required this.isAuthenticated,
    required this.host,
    required this.port,
    required this.connectedAt,
    required this.serverTimeUtc,
    this.serverId,
  });

  final String clientId;
  final bool isAuthenticated;
  final String host;
  final int port;
  final DateTime connectedAt;
  final DateTime serverTimeUtc;
  final String? serverId;
}

/// Le o payload de `sessionResponse` em snapshot tipado.
///
/// Defensivo: timestamps invalidos/ausentes viram `DateTime.now().toUtc()`,
/// `clientId` ausente vira string vazia, `port` invalido vira 0. Cliente
/// deve checar `isAuthenticated` e `clientId.isEmpty` antes de usar.
ServerSession readSessionFromResponse(Message message) {
  final payload = message.payload;
  return ServerSession(
    clientId: (payload['clientId'] as String?) ?? '',
    isAuthenticated: (payload['isAuthenticated'] as bool?) ?? false,
    host: (payload['host'] as String?) ?? '',
    port: (payload['port'] as num?)?.toInt() ?? 0,
    connectedAt: _parseDate(payload['connectedAt']),
    serverTimeUtc: _parseDate(payload['serverTimeUtc']),
    serverId: payload['serverId'] as String?,
  );
}

DateTime _parseDate(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.now().toUtc();
}
