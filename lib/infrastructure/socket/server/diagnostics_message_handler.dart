import 'dart:async';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/diagnostics_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_registry.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/diagnostics_provider.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';

/// Handler de endpoints de diagnostico operacional (PR-3 commit final).
///
/// Despacha para o [DiagnosticsProvider] cabeado e converte outcome
/// em response. cleanupStaging usa idempotency (mutavel); demais
/// (read-only) nao precisam.
class DiagnosticsMessageHandler {
  DiagnosticsMessageHandler({
    DiagnosticsProvider? provider,
    IdempotencyRegistry? idempotencyRegistry,
    DateTime Function()? clock,
  })  : _provider = provider ?? const NotConfiguredDiagnosticsProvider(),
        _idempotencyRegistry = idempotencyRegistry ?? IdempotencyRegistry(),
        _clock = clock ?? DateTime.now;

  final DiagnosticsProvider _provider;
  final IdempotencyRegistry _idempotencyRegistry;
  final DateTime Function() _clock;

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final type = message.header.type;
    if (type == MessageType.getRunLogsRequest) {
      await _handleGetLogs(clientId, message, sendToClient);
    } else if (type == MessageType.getRunErrorDetailsRequest) {
      await _handleGetErrorDetails(clientId, message, sendToClient);
    } else if (type == MessageType.getArtifactMetadataRequest) {
      await _handleGetArtifactMetadata(clientId, message, sendToClient);
    } else if (type == MessageType.cleanupStagingRequest) {
      await _handleCleanupStaging(clientId, message, sendToClient);
    }
  }

  String _runId(Message m) =>
      m.payload['runId'] is String ? m.payload['runId'] as String : '';

  Future<void> _handleGetLogs(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final requestId = message.header.requestId;
    final runId = _runId(message);
    if (runId.isEmpty) {
      await _err(clientId, requestId, 'runId vazio', sendToClient);
      return;
    }
    final maxLines = message.payload['maxLines'] is int
        ? message.payload['maxLines'] as int
        : null;
    final outcome = await _safeCall(
      () => _provider.getRunLogs(runId, maxLines: maxLines),
    );
    if (!outcome.success) {
      await _err(
        clientId,
        requestId,
        outcome.error ?? 'logs nao encontrados',
        sendToClient,
        errorCode: outcome.errorCode ?? ErrorCode.fileNotFound,
      );
      return;
    }
    final data = outcome.data!;
    await sendToClient(
      clientId,
      createGetRunLogsResponse(
        requestId: requestId,
        runId: runId,
        lines: data.lines,
        truncated: data.truncated,
        serverTimeUtc: _clock(),
      ),
    );
  }

  Future<void> _handleGetErrorDetails(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final requestId = message.header.requestId;
    final runId = _runId(message);
    if (runId.isEmpty) {
      await _err(clientId, requestId, 'runId vazio', sendToClient);
      return;
    }
    final outcome = await _safeCall(
      () => _provider.getRunErrorDetails(runId),
    );
    if (!outcome.success) {
      // Para getRunErrorDetails, nao-encontrado e resposta valida
      // (execucao pode nao ter falhado) — entao retornamos response
      // com found=false em vez de error message.
      if (outcome.errorCode == ErrorCode.fileNotFound) {
        await sendToClient(
          clientId,
          createGetRunErrorDetailsResponse(
            requestId: requestId,
            runId: runId,
            serverTimeUtc: _clock(),
            found: false,
          ),
        );
        return;
      }
      await _err(
        clientId,
        requestId,
        outcome.error ?? 'erro inesperado',
        sendToClient,
        errorCode: outcome.errorCode ?? ErrorCode.unknown,
      );
      return;
    }
    final data = outcome.data!;
    await sendToClient(
      clientId,
      createGetRunErrorDetailsResponse(
        requestId: requestId,
        runId: runId,
        serverTimeUtc: _clock(),
        errorMessage: data.errorMessage,
        errorCode: data.errorCode,
        stackTrace: data.stackTrace,
        context: data.context,
      ),
    );
  }

  Future<void> _handleGetArtifactMetadata(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final requestId = message.header.requestId;
    final runId = _runId(message);
    if (runId.isEmpty) {
      await _err(clientId, requestId, 'runId vazio', sendToClient);
      return;
    }
    final outcome = await _safeCall(
      () => _provider.getArtifactMetadata(runId),
    );
    if (!outcome.success) {
      if (outcome.errorCode == ErrorCode.artifactExpired) {
        await _err(
          clientId,
          requestId,
          outcome.error ?? ErrorCode.artifactExpired.defaultMessage,
          sendToClient,
          errorCode: ErrorCode.artifactExpired,
        );
        return;
      }
      // Nao encontrado: sem artefato no staging (ainda nao pronto ou path legado).
      if (outcome.errorCode == ErrorCode.fileNotFound) {
        await sendToClient(
          clientId,
          createGetArtifactMetadataResponse(
            requestId: requestId,
            runId: runId,
            serverTimeUtc: _clock(),
            found: false,
          ),
        );
        return;
      }
      await _err(
        clientId,
        requestId,
        outcome.error ?? 'erro inesperado',
        sendToClient,
        errorCode: outcome.errorCode ?? ErrorCode.unknown,
      );
      return;
    }
    final data = outcome.data!;
    await sendToClient(
      clientId,
      createGetArtifactMetadataResponse(
        requestId: requestId,
        runId: runId,
        serverTimeUtc: _clock(),
        sizeBytes: data.sizeBytes,
        hashAlgorithm: data.hashAlgorithm,
        hashValue: data.hashValue,
        stagingPath: data.stagingPath,
        expiresAt: data.expiresAt,
      ),
    );
  }

  Future<void> _handleCleanupStaging(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final requestId = message.header.requestId;
    final runId = _runId(message);
    if (runId.isEmpty) {
      await _err(clientId, requestId, 'runId vazio', sendToClient);
      return;
    }
    final idempotencyKey = getIdempotencyKey(message);
    try {
      final response = await _idempotencyRegistry.runIdempotent<Message>(
        key: idempotencyKey,
        compute: () async {
          final outcome = await _safeCall(
            () => _provider.cleanupStaging(runId),
          );
          if (!outcome.success) {
            // cleanup pode falhar normalmente (ja limpo, nao existe)
            // — retornamos response com cleaned=false em vez de error.
            return createCleanupStagingResponse(
              requestId: requestId,
              runId: runId,
              cleaned: false,
              serverTimeUtc: _clock(),
              message: outcome.error ?? 'nada a limpar',
            );
          }
          final data = outcome.data!;
          return createCleanupStagingResponse(
            requestId: requestId,
            runId: runId,
            cleaned: data.cleaned,
            serverTimeUtc: _clock(),
            bytesFreed: data.bytesFreed,
            message: data.message,
          );
        },
      );
      await sendToClient(clientId, response);
    } on Object catch (e, st) {
      LoggerService.warning('cleanupStaging error: $e', e, st);
      await _err(
        clientId,
        requestId,
        'Erro interno: $e',
        sendToClient,
        errorCode: ErrorCode.unknown,
      );
    }
  }

  Future<DiagnosticsOutcome<T>> _safeCall<T>(
    Future<DiagnosticsOutcome<T>> Function() compute,
  ) async {
    try {
      return await compute();
    } on Object catch (e, st) {
      LoggerService.warning('DiagnosticsMessageHandler: provider threw: $e', e, st);
      return DiagnosticsOutcome<T>.failure(
        error: 'Erro interno: $e',
        errorCode: ErrorCode.unknown,
      );
    }
  }

  Future<void> _err(
    String clientId,
    int requestId,
    String message,
    SendToClient sendToClient, {
    ErrorCode errorCode = ErrorCode.invalidRequest,
  }) async {
    await sendToClient(
      clientId,
      createErrorMessage(
        requestId: requestId,
        errorMessage: message,
        errorCode: errorCode,
      ),
    );
  }
}
