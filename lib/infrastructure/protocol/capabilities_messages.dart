import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/protocol_versions.dart';
import 'package:backup_database/infrastructure/protocol/response_envelope.dart';

/// Constroi um `capabilitiesRequest` (cliente -> servidor) sem payload.
///
/// O servidor responde com `capabilitiesResponse` informando versoes,
/// flags de feature e parametros operacionais. Implementa M4.1 do plano
/// e a parte cliente-facing de ADR-003.
Message createCapabilitiesRequestMessage({int requestId = 0}) {
  const payload = <String, dynamic>{};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.capabilitiesRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Constroi um `capabilitiesResponse` (servidor -> cliente).
///
/// Para preservar backward compat e flexibilidade, todos os campos sao
/// opcionais. O servidor atual emite o conjunto minimo definido em
/// ADR-003. Campos adicionais podem ser anexados em deploys futuros sem
/// quebrar clientes que so leem o subset que conhecem.
Message createCapabilitiesResponseMessage({
  required int requestId,
  required int protocolVersion,
  required int wireVersion,
  required bool supportsRunId,
  required bool supportsResume,
  required bool supportsArtifactRetention,
  required bool supportsChunkAck,
  required bool supportsExecutionQueue,
  required int chunkSize,
  required String compression,
  required DateTime serverTimeUtc,
}) {
  final payload = wrapSuccessResponse(<String, dynamic>{
    'protocolVersion': protocolVersion,
    'wireVersion': wireVersion,
    'supportsRunId': supportsRunId,
    'supportsResume': supportsResume,
    'supportsArtifactRetention': supportsArtifactRetention,
    'supportsChunkAck': supportsChunkAck,
    'supportsExecutionQueue': supportsExecutionQueue,
    'chunkSize': chunkSize,
    'compression': compression,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
  });
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.capabilitiesResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

bool isCapabilitiesRequestMessage(Message message) =>
    message.header.type == MessageType.capabilitiesRequest;

bool isCapabilitiesResponseMessage(Message message) =>
    message.header.type == MessageType.capabilitiesResponse;

/// Snapshot tipado das capabilities anunciadas pelo servidor.
///
/// Cliente usa como **gate de feature** (M4.1): habilita code path novo
/// somente quando a flag correspondente e `true`. Quando o servidor for
/// `v1` (sem `getServerCapabilities` implementado), o cliente pode usar
/// [ServerCapabilities.legacyDefault] para assumir defaults
/// conservadores — nada de runId, sem fila, sem retencao, etc.
class ServerCapabilities {
  const ServerCapabilities({
    required this.protocolVersion,
    required this.wireVersion,
    required this.supportsRunId,
    required this.supportsResume,
    required this.supportsArtifactRetention,
    required this.supportsChunkAck,
    required this.supportsExecutionQueue,
    required this.chunkSize,
    required this.compression,
    required this.serverTimeUtc,
  });

  /// Defaults para servidor `v1` legado que nao implementa
  /// `getServerCapabilities`. Cliente deve usar este snapshot quando a
  /// chamada falhar com `error`/timeout. Reflete o estado real do
  /// codebase antes de ADR-003 + M2.3.
  static const ServerCapabilities legacyDefault = ServerCapabilities(
    protocolVersion: 1,
    wireVersion: kCurrentWireVersion,
    supportsRunId: false,
    supportsResume: true,
    supportsArtifactRetention: false,
    supportsChunkAck: false,
    supportsExecutionQueue: false,
    chunkSize: 65536,
    compression: 'gzip',
    serverTimeUtc: null,
  );

  final int protocolVersion;
  final int wireVersion;
  final bool supportsRunId;
  final bool supportsResume;
  final bool supportsArtifactRetention;
  final bool supportsChunkAck;
  final bool supportsExecutionQueue;
  final int chunkSize;
  final String compression;

  /// `null` quando o servidor nao reportou (ex.: legado). Quando
  /// presente, util para detectar drift de relogio cliente vs servidor.
  final DateTime? serverTimeUtc;
}

/// Le o payload de `capabilitiesResponse` em snapshot tipado.
///
/// Tolera campos ausentes: usa defaults conservadores compativeis com
/// servidor `v1` legado. Isso permite ao cliente novo conectar em
/// servidor mais antigo sem quebrar (degradacao graceful M4.1).
ServerCapabilities readCapabilitiesFromResponse(Message message) {
  final payload = message.payload;
  return ServerCapabilities(
    protocolVersion: (payload['protocolVersion'] as num?)?.toInt() ?? 1,
    wireVersion:
        (payload['wireVersion'] as num?)?.toInt() ?? kCurrentWireVersion,
    supportsRunId: (payload['supportsRunId'] as bool?) ?? false,
    supportsResume: (payload['supportsResume'] as bool?) ?? true,
    supportsArtifactRetention:
        (payload['supportsArtifactRetention'] as bool?) ?? false,
    supportsChunkAck: (payload['supportsChunkAck'] as bool?) ?? false,
    supportsExecutionQueue:
        (payload['supportsExecutionQueue'] as bool?) ?? false,
    chunkSize: (payload['chunkSize'] as num?)?.toInt() ?? 65536,
    compression: (payload['compression'] as String?) ?? 'gzip',
    serverTimeUtc: _parseServerTime(payload['serverTimeUtc']),
  );
}

DateTime? _parseServerTime(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
