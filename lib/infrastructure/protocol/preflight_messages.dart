import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

/// Severidade de uma checagem de preflight.
///
/// `blocking`: falha impede execucao remota (ex.: ferramenta de
///   compactacao ausente, pasta temp inacessivel).
/// `warning`: condicao subotima mas nao impede execucao (ex.: pouco
///   espaco em disco mas suficiente para um backup).
/// `info`: apenas informativo (ex.: versao da ferramenta detectada).
enum PreflightSeverity {
  blocking,
  warning,
  info;

  static PreflightSeverity fromString(String value) {
    return values.firstWhere(
      (s) => s.name == value,
      orElse: () => PreflightSeverity.info,
    );
  }
}

/// Status agregado de um preflight completo.
///
/// `passed`: todos os checks passaram.
/// `passedWithWarnings`: nenhum bloqueante falhou, mas algum warning
///   foi disparado. Cliente pode disparar backup mas deve avisar
///   operador.
/// `blocked`: pelo menos um check `blocking` falhou. Cliente NAO deve
///   disparar backup ate o problema ser resolvido.
enum PreflightStatus {
  passed,
  passedWithWarnings,
  blocked;

  static PreflightStatus fromString(String value) {
    return values.firstWhere(
      (s) => s.name == value,
      orElse: () => PreflightStatus.blocked,
    );
  }

  /// Atalho que cliente pode usar como gate sincrono. Falha-fechado:
  /// status desconhecido vira `false`.
  bool get isOk =>
      this == PreflightStatus.passed || this == PreflightStatus.passedWithWarnings;
}

/// Resultado tipado de uma checagem individual.
///
/// [name] e o identificador estavel do check (ex.: "compression_tool",
///   "temp_dir_writable", "disk_space"). Cliente pode mapear para
///   ações específicas (ex.: instalar ferramenta, liberar espaço).
/// [passed] indica se a verificacao passou.
/// [severity] e o nivel de impacto da falha (so relevante quando
///   `passed == false`).
/// [message] descreve a condicao em linguagem natural (PT-BR).
/// [details] e mapa opcional para dados estruturados (ex.: bytes
///   livres, caminho verificado).
class PreflightCheckResult {
  const PreflightCheckResult({
    required this.name,
    required this.passed,
    required this.severity,
    required this.message,
    this.details = const <String, dynamic>{},
  });

  final String name;
  final bool passed;
  final PreflightSeverity severity;
  final String message;
  final Map<String, dynamic> details;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'passed': passed,
      'severity': severity.name,
      'message': message,
      if (details.isNotEmpty) 'details': details,
    };
  }

  factory PreflightCheckResult.fromMap(Map<String, dynamic> map) {
    return PreflightCheckResult(
      name: (map['name'] as String?) ?? '',
      passed: (map['passed'] as bool?) ?? false,
      severity: PreflightSeverity.fromString(
        (map['severity'] as String?) ?? 'info',
      ),
      message: (map['message'] as String?) ?? '',
      details: _parseDetails(map['details']),
    );
  }
}

Map<String, dynamic> _parseDetails(Object? raw) {
  if (raw is! Map) return const <String, dynamic>{};
  return Map<String, dynamic>.from(raw);
}

/// Constroi um `preflightRequest` (cliente -> servidor) sem payload.
///
/// O servidor executa todos os checks registrados (ferramenta de
/// compactacao, pasta temp gravavel, espaco em disco, etc.) e responde
/// com status agregado + lista de checks. Implementa F1.8 do plano.
Message createPreflightRequestMessage({int requestId = 0}) {
  const payload = <String, dynamic>{};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.preflightRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Constroi um `preflightResponse` (servidor -> cliente).
Message createPreflightResponseMessage({
  required int requestId,
  required PreflightStatus status,
  required List<PreflightCheckResult> checks,
  required DateTime serverTimeUtc,
  String? message,
}) {
  final payload = <String, dynamic>{
    'status': status.name,
    'checks': checks.map((c) => c.toMap()).toList(),
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
    ...?(message != null ? {'message': message} : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.preflightResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

bool isPreflightRequestMessage(Message message) =>
    message.header.type == MessageType.preflightRequest;

bool isPreflightResponseMessage(Message message) =>
    message.header.type == MessageType.preflightResponse;

/// Snapshot tipado do resultado de preflight (lado cliente).
class PreflightResult {
  const PreflightResult({
    required this.status,
    required this.checks,
    required this.serverTimeUtc,
    this.message,
  });

  final PreflightStatus status;
  final List<PreflightCheckResult> checks;
  final DateTime serverTimeUtc;
  final String? message;

  /// Lista filtrada de checks que falharam com severidade `blocking`.
  /// Cliente exibe esses como erros que precisam ser resolvidos.
  List<PreflightCheckResult> get blockingFailures => checks
      .where((c) => !c.passed && c.severity == PreflightSeverity.blocking)
      .toList();

  /// Lista filtrada de checks que falharam com severidade `warning`.
  /// Cliente exibe como avisos sem bloquear o disparo.
  List<PreflightCheckResult> get warnings => checks
      .where((c) => !c.passed && c.severity == PreflightSeverity.warning)
      .toList();

  /// Atalho para gate sincrono na UI.
  bool get isOk => status.isOk;
  bool get isBlocked => status == PreflightStatus.blocked;
  bool get hasWarnings => status == PreflightStatus.passedWithWarnings;
}

/// Le o payload de `preflightResponse` em snapshot tipado.
///
/// Defensivo: status invalido vira `blocked` (fail-closed), checks
/// ausentes viram lista vazia, timestamps invalidos viram `now()`.
PreflightResult readPreflightFromResponse(Message message) {
  final payload = message.payload;
  return PreflightResult(
    status: PreflightStatus.fromString(
      payload['status'] as String? ?? 'blocked',
    ),
    checks: _parseChecks(payload['checks']),
    serverTimeUtc: _parseDate(payload['serverTimeUtc']),
    message: payload['message'] as String?,
  );
}

List<PreflightCheckResult> _parseChecks(Object? raw) {
  if (raw is! List) return const <PreflightCheckResult>[];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(PreflightCheckResult.fromMap)
      .toList();
}

DateTime _parseDate(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.now().toUtc();
}
