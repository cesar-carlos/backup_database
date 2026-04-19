import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

/// Item enfileirado aguardando slot livre para execucao remota.
///
/// Emitido por `getExecutionQueue` quando ha execucao em curso e
/// novos disparos sao colocados em fila (PR-3b). Ate la, a fila
/// permanece sempre vazia (mutex global de 1 backup por servidor
/// rejeita o segundo disparo manual com erro; agendados nao acumulam
/// porque scheduler local so dispara apos o anterior terminar).
class QueuedExecution {
  const QueuedExecution({
    required this.runId,
    required this.scheduleId,
    required this.queuedAt,
    required this.queuedPosition,
    this.requestedBy,
  });

  final String runId;
  final String scheduleId;
  final DateTime queuedAt;

  /// Posicao 1-based na fila. `1` significa "proximo a ser executado".
  final int queuedPosition;

  /// `clientId` que originou o disparo enfileirado (quando conhecido).
  final String? requestedBy;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'runId': runId,
      'scheduleId': scheduleId,
      'queuedAt': queuedAt.toUtc().toIso8601String(),
      'queuedPosition': queuedPosition,
      ...?(requestedBy != null ? {'requestedBy': requestedBy} : null),
    };
  }

  factory QueuedExecution.fromMap(Map<String, dynamic> map) {
    return QueuedExecution(
      runId: (map['runId'] as String?) ?? '',
      scheduleId: (map['scheduleId'] as String?) ?? '',
      queuedAt: _parseDate(map['queuedAt']),
      queuedPosition: (map['queuedPosition'] as num?)?.toInt() ?? 0,
      requestedBy: map['requestedBy'] as String?,
    );
  }
}

/// Constroi um `executionQueueRequest` (cliente -> servidor) sem payload.
Message createExecutionQueueRequestMessage({int requestId = 0}) {
  const payload = <String, dynamic>{};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.executionQueueRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Constroi um `executionQueueResponse` (servidor -> cliente).
///
/// [queue] lista ordenada por `queuedPosition` ascendente.
/// [maxQueueSize] limite operacional (default 50 conforme M8 do plano).
/// [serverTimeUtc] sempre presente para drift de relogio.
Message createExecutionQueueResponseMessage({
  required int requestId,
  required List<QueuedExecution> queue,
  required int maxQueueSize,
  required DateTime serverTimeUtc,
}) {
  final payload = <String, dynamic>{
    'queue': queue.map((q) => q.toMap()).toList(),
    'totalQueued': queue.length,
    'maxQueueSize': maxQueueSize,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.executionQueueResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

bool isExecutionQueueRequestMessage(Message message) =>
    message.header.type == MessageType.executionQueueRequest;

bool isExecutionQueueResponseMessage(Message message) =>
    message.header.type == MessageType.executionQueueResponse;

/// Snapshot tipado da fila de execucoes (lado cliente).
class ExecutionQueueResult {
  const ExecutionQueueResult({
    required this.queue,
    required this.totalQueued,
    required this.maxQueueSize,
    required this.serverTimeUtc,
  });

  final List<QueuedExecution> queue;
  final int totalQueued;
  final int maxQueueSize;
  final DateTime serverTimeUtc;

  /// `true` quando nao ha itens enfileirados.
  bool get isEmpty => queue.isEmpty;

  /// `true` quando a fila atingiu o limite — proximos disparos serao
  /// rejeitados com `429 QUEUE_OVERFLOW` (M8 do plano).
  bool get isFull => totalQueued >= maxQueueSize;

  /// Quantos slots ainda cabem antes de atingir o limite.
  int get availableSlots => (maxQueueSize - totalQueued).clamp(0, maxQueueSize);
}

/// Le o payload de `executionQueueResponse` em snapshot tipado.
///
/// Defensivo: `queue` ausente vira lista vazia, `maxQueueSize` ausente
/// usa default 50 do plano, timestamps invalidos viram `now()`.
ExecutionQueueResult readExecutionQueueFromResponse(Message message) {
  final payload = message.payload;
  final rawQueue = payload['queue'];
  final queue = rawQueue is List
      ? rawQueue
          .whereType<Map<String, dynamic>>()
          .map(QueuedExecution.fromMap)
          .toList()
      : <QueuedExecution>[];
  return ExecutionQueueResult(
    queue: queue,
    totalQueued: (payload['totalQueued'] as num?)?.toInt() ?? queue.length,
    maxQueueSize: (payload['maxQueueSize'] as num?)?.toInt() ?? 50,
    serverTimeUtc: _parseDate(payload['serverTimeUtc']),
  );
}

DateTime _parseDate(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.now().toUtc();
}
