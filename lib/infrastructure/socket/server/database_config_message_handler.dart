import 'dart:async';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/database_connection_prober.dart';

/// Handler que responde `testDatabaseConnectionRequest` (PR-2).
///
/// Despacha para o [DatabaseConnectionProber] cabeado e converte o
/// outcome em `testDatabaseConnectionResponse`, ja com envelope
/// REST-like (`success`/`statusCode`).
///
/// Nao acopla a drivers concretos — toda a logica de "abrir conexao
/// e fechar" fica em `DatabaseConnectionProber`. Isso mantem o
/// handler trivial de testar e permite swap por implementacao
/// alternativa (ex.: prober que consulta cache, prober mockado em
/// testes de integracao).
class DatabaseConfigMessageHandler {
  DatabaseConfigMessageHandler({
    DatabaseConnectionProber? prober,
    DateTime Function()? clock,
  })  : _prober = prober ?? const NotConfiguredProber(),
        _clock = clock ?? DateTime.now;

  final DatabaseConnectionProber _prober;
  final DateTime Function() _clock;

  Future<void> handle(
    String clientId,
    Message message,
    Future<void> Function(String clientId, Message message) sendToClient,
  ) async {
    if (message.header.type != MessageType.testDatabaseConnectionRequest) {
      return;
    }

    final requestId = message.header.requestId;
    final payload = message.payload;

    // Defesa F0.4 / F0.6: tipos errados ou faltando -> 400 invalidRequest
    final databaseTypeRaw = payload['databaseType'];
    if (databaseTypeRaw is! String) {
      await _sendError(
        clientId,
        sendToClient,
        requestId,
        'Campo `databaseType` ausente ou nao-string',
        ErrorCode.invalidRequest,
      );
      return;
    }
    final databaseType = RemoteDatabaseType.fromWire(databaseTypeRaw);
    if (databaseType == null) {
      await _sendError(
        clientId,
        sendToClient,
        requestId,
        '`databaseType` nao suportado: $databaseTypeRaw',
        ErrorCode.invalidRequest,
      );
      return;
    }

    final hasId = payload['databaseConfigId'] is String &&
        (payload['databaseConfigId'] as String).isNotEmpty;
    final hasConfig = payload['config'] is Map;
    if (hasId == hasConfig) {
      // Ambos ou nenhum -> contrato violado
      await _sendError(
        clientId,
        sendToClient,
        requestId,
        'Informe APENAS um de `databaseConfigId` ou `config` (XOR)',
        ErrorCode.invalidRequest,
      );
      return;
    }

    final configRef = hasId
        ? DatabaseConfigById(payload['databaseConfigId'] as String)
        : DatabaseConfigAdhoc(
            Map<String, dynamic>.from(payload['config'] as Map),
          );

    Duration? timeout;
    final timeoutRaw = payload['timeoutMs'];
    if (timeoutRaw is int && timeoutRaw > 0) {
      timeout = Duration(milliseconds: timeoutRaw);
    }

    DatabaseProbeOutcome outcome;
    try {
      outcome = await _prober.probe(
        databaseType: databaseType,
        configRef: configRef,
        timeout: timeout,
      );
    } on Object catch (e, st) {
      // Fail-closed: prober jogou exception nao-tratada -> 500
      LoggerService.warning(
        'DatabaseConfigMessageHandler: prober threw for '
        '${databaseType.wireName}: $e',
        e,
        st,
      );
      outcome = DatabaseProbeOutcome.failure(
        latencyMs: 0,
        error: 'Erro interno do prober: $e',
        errorCode: ErrorCode.unknown,
      );
    }

    await sendToClient(
      clientId,
      createTestDatabaseConnectionResponse(
        requestId: requestId,
        connected: outcome.connected,
        latencyMs: outcome.latencyMs,
        serverTimeUtc: _clock(),
        error: outcome.error,
        errorCode: outcome.errorCode,
        details: outcome.details,
      ),
    );
  }

  Future<void> _sendError(
    String clientId,
    Future<void> Function(String clientId, Message message) sendToClient,
    int requestId,
    String message,
    ErrorCode errorCode,
  ) async {
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
