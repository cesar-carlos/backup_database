import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

/// Status agregado de saude reportado pelo servidor.
///
/// `ok`: todos os subsistemas operando normalmente.
/// `degraded`: servidor responde mas algum subsistema esta com problemas
///   (ex.: persistencia lenta, fila proxima do limite). Cliente deve
///   continuar operando, mas exibir alerta operacional.
/// `unhealthy`: subsistema critico fora do ar (ex.: banco inacessivel).
///   Cliente nao deve disparar novos backups remotos ate `ok`.
enum ServerHealthStatus {
  ok,
  degraded,
  unhealthy;

  static ServerHealthStatus fromString(String value) {
    return values.firstWhere(
      (s) => s.name == value,
      orElse: () => ServerHealthStatus.unhealthy,
    );
  }
}

/// Constroi um `healthRequest` (cliente -> servidor) sem payload.
///
/// O servidor responde com `healthResponse` informando status agregado
/// e checks individuais. Implementa M1.10 do plano (API de saude
/// minima do servidor) + parte de PR-1.
Message createHealthRequestMessage({int requestId = 0}) {
  const payload = <String, dynamic>{};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.healthRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Constroi um `healthResponse` (servidor -> cliente).
///
/// Campos minimos:
/// - [status]: status agregado.
/// - [checks]: mapa `nome -> bool` de checks individuais (ex.:
///   `{'socket': true, 'database': true, 'staging': false}`).
/// - [serverTimeUtc]: util para detectar drift de relogio.
/// - [uptimeSeconds]: tempo desde o start do servidor (debug/troubleshooting).
///
/// Mensagem auxiliar opcional [message] descreve o motivo de
/// `degraded`/`unhealthy` quando aplicavel.
Message createHealthResponseMessage({
  required int requestId,
  required ServerHealthStatus status,
  required Map<String, bool> checks,
  required DateTime serverTimeUtc,
  required int uptimeSeconds,
  String? message,
}) {
  final payload = <String, dynamic>{
    'status': status.name,
    'checks': checks,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
    'uptimeSeconds': uptimeSeconds,
    ...?(message != null ? {'message': message} : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.healthResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

bool isHealthRequestMessage(Message message) =>
    message.header.type == MessageType.healthRequest;

bool isHealthResponseMessage(Message message) =>
    message.header.type == MessageType.healthResponse;

/// Snapshot tipado da saude do servidor (lado cliente).
///
/// Cliente pode usar para:
/// - exibir indicador de status no dashboard;
/// - bloquear disparo de backup quando `unhealthy`;
/// - alertar operador quando `degraded`;
/// - calcular drift de relogio (`serverTimeUtc - clientTimeUtc`).
class ServerHealth {
  const ServerHealth({
    required this.status,
    required this.checks,
    required this.serverTimeUtc,
    required this.uptimeSeconds,
    this.message,
  });

  final ServerHealthStatus status;
  final Map<String, bool> checks;
  final DateTime serverTimeUtc;
  final int uptimeSeconds;
  final String? message;

  bool get isOk => status == ServerHealthStatus.ok;
  bool get isUnhealthy => status == ServerHealthStatus.unhealthy;
}

/// Le o payload de `healthResponse` em snapshot tipado.
///
/// Tolera campos ausentes/invalidos: `status` desconhecido vira
/// `unhealthy` (fail-closed), `checks` ausente vira mapa vazio,
/// timestamps invalidos viram `DateTime.now().toUtc()`. Defesa
/// preventiva contra servidor com bug — cliente continua usavel.
ServerHealth readHealthFromResponse(Message message) {
  final payload = message.payload;
  return ServerHealth(
    status: ServerHealthStatus.fromString(
      payload['status'] as String? ?? 'unhealthy',
    ),
    checks: _parseChecks(payload['checks']),
    serverTimeUtc: _parseServerTime(payload['serverTimeUtc']),
    uptimeSeconds: (payload['uptimeSeconds'] as num?)?.toInt() ?? 0,
    message: payload['message'] as String?,
  );
}

Map<String, bool> _parseChecks(Object? raw) {
  if (raw is! Map) return const <String, bool>{};
  final result = <String, bool>{};
  raw.forEach((key, value) {
    if (key is String && value is bool) {
      result[key] = value;
    }
  });
  return result;
}

DateTime _parseServerTime(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.now().toUtc();
}
