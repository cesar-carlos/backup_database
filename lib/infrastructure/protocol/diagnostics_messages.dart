import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/response_envelope.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';

/// Endpoints de diagnostico operacional (PR-3 commit final).
///
/// Todos sao read-only (idempotency nao necessaria). Implementacao
/// concreta delegada via DI (DiagnosticsProvider) — handler conhece
/// apenas a interface, nao os repositorios concretos de logs/staging.

// ---------------------------------------------------------------------------
// getRunLogs: cliente busca logs de uma execucao especifica por runId.
// ---------------------------------------------------------------------------

Message createGetRunLogsRequest({
  required String runId,
  int? maxLines,
  int requestId = 0,
}) {
  if (runId.isEmpty) {
    throw ArgumentError('getRunLogs: runId obrigatorio');
  }
  final payload = <String, dynamic>{
    'runId': runId,
    if (maxLines != null) 'maxLines': maxLines,
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.getRunLogsRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createGetRunLogsResponse({
  required int requestId,
  required String runId,
  required List<String> lines,
  required DateTime serverTimeUtc,
  bool truncated = false,
}) {
  final base = <String, dynamic>{
    'runId': runId,
    'lines': lines,
    'truncated': truncated,
    'totalLines': lines.length,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
  };
  final payload = wrapSuccessResponse(base);
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.getRunLogsResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

class RunLogsResult {
  const RunLogsResult({
    required this.runId,
    required this.lines,
    required this.truncated,
    required this.totalLines,
    required this.serverTimeUtc,
  });

  final String runId;
  final List<String> lines;
  final bool truncated;
  final int totalLines;
  final DateTime serverTimeUtc;

  bool get isEmpty => lines.isEmpty;
}

RunLogsResult readRunLogsResponse(Message message) {
  final p = message.payload;
  final raw = p['lines'];
  final lines = raw is List ? raw.whereType<String>().toList() : <String>[];
  return RunLogsResult(
    runId: p['runId'] is String ? p['runId'] as String : '',
    lines: lines,
    truncated: p['truncated'] is bool && p['truncated'] as bool,
    totalLines: p['totalLines'] is int ? p['totalLines'] as int : lines.length,
    serverTimeUtc: p['serverTimeUtc'] is String
        ? (DateTime.tryParse(p['serverTimeUtc'] as String) ??
            DateTime.fromMillisecondsSinceEpoch(0).toUtc())
        : DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
  );
}

// ---------------------------------------------------------------------------
// getRunErrorDetails: cliente busca detalhes do erro que causou
// `failed`. Inclui stack trace, mensagem, errorCode estruturado.
// ---------------------------------------------------------------------------

Message createGetRunErrorDetailsRequest({
  required String runId,
  int requestId = 0,
}) {
  if (runId.isEmpty) {
    throw ArgumentError('getRunErrorDetails: runId obrigatorio');
  }
  final payload = <String, dynamic>{'runId': runId};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.getRunErrorDetailsRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createGetRunErrorDetailsResponse({
  required int requestId,
  required String runId,
  required DateTime serverTimeUtc,
  String? errorMessage,
  ErrorCode? errorCode,
  String? stackTrace,
  Map<String, dynamic>? context,
  bool found = true,
}) {
  final base = <String, dynamic>{
    'runId': runId,
    'found': found,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (errorCode != null) 'errorCode': errorCode.code,
    if (stackTrace != null) 'stackTrace': stackTrace,
    if (context != null && context.isNotEmpty) 'context': context,
  };
  final statusCode = found ? StatusCodes.ok : StatusCodes.notFound;
  final payload = wrapSuccessResponse(base, statusCode: statusCode);
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.getRunErrorDetailsResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

class RunErrorDetailsResult {
  const RunErrorDetailsResult({
    required this.runId,
    required this.found,
    required this.serverTimeUtc,
    this.errorMessage,
    this.errorCode,
    this.stackTrace,
    this.context,
  });

  final String runId;
  final bool found;
  final DateTime serverTimeUtc;
  final String? errorMessage;
  final ErrorCode? errorCode;
  final String? stackTrace;
  final Map<String, dynamic>? context;
}

RunErrorDetailsResult readRunErrorDetailsResponse(Message message) {
  final p = message.payload;
  final errorCodeRaw = p['errorCode'] is String ? p['errorCode'] as String : null;
  return RunErrorDetailsResult(
    runId: p['runId'] is String ? p['runId'] as String : '',
    found: p['found'] is bool && p['found'] as bool,
    serverTimeUtc: p['serverTimeUtc'] is String
        ? (DateTime.tryParse(p['serverTimeUtc'] as String) ??
            DateTime.fromMillisecondsSinceEpoch(0).toUtc())
        : DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
    errorMessage: p['errorMessage'] is String ? p['errorMessage'] as String : null,
    errorCode: errorCodeRaw != null ? ErrorCode.fromString(errorCodeRaw) : null,
    stackTrace: p['stackTrace'] is String ? p['stackTrace'] as String : null,
    context: p['context'] is Map ? Map<String, dynamic>.from(p['context'] as Map) : null,
  );
}

// ---------------------------------------------------------------------------
// getArtifactMetadata: cliente consulta metadata do arquivo final
// (tamanho, hash, expiracao, path no staging do servidor).
// ---------------------------------------------------------------------------

Message createGetArtifactMetadataRequest({
  required String runId,
  int requestId = 0,
}) {
  if (runId.isEmpty) {
    throw ArgumentError('getArtifactMetadata: runId obrigatorio');
  }
  final payload = <String, dynamic>{'runId': runId};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.getArtifactMetadataRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createGetArtifactMetadataResponse({
  required int requestId,
  required String runId,
  required DateTime serverTimeUtc,
  bool found = true,
  int? sizeBytes,
  String? hashAlgorithm,
  String? hashValue,
  String? stagingPath,
  DateTime? expiresAt,
}) {
  final base = <String, dynamic>{
    'runId': runId,
    'found': found,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
    if (sizeBytes != null) 'sizeBytes': sizeBytes,
    if (hashAlgorithm != null) 'hashAlgorithm': hashAlgorithm,
    if (hashValue != null) 'hashValue': hashValue,
    if (stagingPath != null) 'stagingPath': stagingPath,
    if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
  final statusCode = found ? StatusCodes.ok : StatusCodes.notFound;
  final payload = wrapSuccessResponse(base, statusCode: statusCode);
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.getArtifactMetadataResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

class ArtifactMetadataResult {
  const ArtifactMetadataResult({
    required this.runId,
    required this.found,
    required this.serverTimeUtc,
    this.sizeBytes,
    this.hashAlgorithm,
    this.hashValue,
    this.stagingPath,
    this.expiresAt,
  });

  final String runId;
  final bool found;
  final DateTime serverTimeUtc;
  final int? sizeBytes;
  final String? hashAlgorithm;
  final String? hashValue;
  final String? stagingPath;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().toUtc());
}

ArtifactMetadataResult readArtifactMetadataResponse(Message message) {
  final p = message.payload;
  return ArtifactMetadataResult(
    runId: p['runId'] is String ? p['runId'] as String : '',
    found: p['found'] is bool && p['found'] as bool,
    serverTimeUtc: p['serverTimeUtc'] is String
        ? (DateTime.tryParse(p['serverTimeUtc'] as String) ??
            DateTime.fromMillisecondsSinceEpoch(0).toUtc())
        : DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
    sizeBytes: p['sizeBytes'] is int ? p['sizeBytes'] as int : null,
    hashAlgorithm: p['hashAlgorithm'] is String ? p['hashAlgorithm'] as String : null,
    hashValue: p['hashValue'] is String ? p['hashValue'] as String : null,
    stagingPath: p['stagingPath'] is String ? p['stagingPath'] as String : null,
    expiresAt: p['expiresAt'] is String
        ? DateTime.tryParse(p['expiresAt'] as String)
        : null,
  );
}

// ---------------------------------------------------------------------------
// cleanupStaging: cliente solicita limpeza do staging do servidor.
// Migra responsabilidade do cliente -> servidor (P0.3 do plano).
// ---------------------------------------------------------------------------

Message createCleanupStagingRequest({
  required String runId,
  String? idempotencyKey,
  int requestId = 0,
}) {
  if (runId.isEmpty) {
    throw ArgumentError('cleanupStaging: runId obrigatorio');
  }
  final payload = <String, dynamic>{
    'runId': runId,
    if (idempotencyKey != null && idempotencyKey.isNotEmpty)
      'idempotencyKey': idempotencyKey,
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.cleanupStagingRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createCleanupStagingResponse({
  required int requestId,
  required String runId,
  required bool cleaned,
  required DateTime serverTimeUtc,
  int? bytesFreed,
  String? message,
}) {
  final base = <String, dynamic>{
    'runId': runId,
    'cleaned': cleaned,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
    if (bytesFreed != null) 'bytesFreed': bytesFreed,
    if (message != null) 'message': message,
  };
  final payload = wrapSuccessResponse(base);
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.cleanupStagingResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

class CleanupStagingResult {
  const CleanupStagingResult({
    required this.runId,
    required this.cleaned,
    required this.serverTimeUtc,
    this.bytesFreed,
    this.message,
  });

  final String runId;
  final bool cleaned;
  final DateTime serverTimeUtc;
  final int? bytesFreed;
  final String? message;
}

CleanupStagingResult readCleanupStagingResponse(Message message) {
  final p = message.payload;
  return CleanupStagingResult(
    runId: p['runId'] is String ? p['runId'] as String : '',
    cleaned: p['cleaned'] is bool && p['cleaned'] as bool,
    serverTimeUtc: p['serverTimeUtc'] is String
        ? (DateTime.tryParse(p['serverTimeUtc'] as String) ??
            DateTime.fromMillisecondsSinceEpoch(0).toUtc())
        : DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
    bytesFreed: p['bytesFreed'] is int ? p['bytesFreed'] as int : null,
    message: p['message'] is String ? p['message'] as String : null,
  );
}
