import 'dart:async';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_policy.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_registry.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_store.dart';
import 'package:backup_database/infrastructure/socket/server/database_connection_prober.dart';
import 'package:backup_database/infrastructure/socket/server/socket_error_sender.dart';

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
    DatabaseConfigStore? store,
    IdempotencyRegistry? idempotencyRegistry,
    DateTime Function()? clock,
    bool supportsFirebird = true,
  }) : _prober = prober ?? const NotConfiguredProber(),
       _store = store ?? const NotConfiguredDatabaseConfigStore(),
       _idempotencyRegistry = idempotencyRegistry ?? IdempotencyRegistry(),
       _clock = clock ?? DateTime.now,
       _supportsFirebird = supportsFirebird;

  final DatabaseConnectionProber _prober;
  final DatabaseConfigStore _store;
  final IdempotencyRegistry _idempotencyRegistry;
  final DateTime Function() _clock;
  final bool _supportsFirebird;

  Future<void> handle(
    String clientId,
    Message message,
    Future<void> Function(String clientId, Message message) sendToClient,
  ) async {
    final type = message.header.type;
    if (type == MessageType.listDatabaseConfigsRequest) {
      await _handleList(clientId, message, sendToClient);
      return;
    }
    if (type == MessageType.createDatabaseConfigRequest ||
        type == MessageType.updateDatabaseConfigRequest ||
        type == MessageType.deleteDatabaseConfigRequest) {
      await _handleMutation(clientId, message, sendToClient);
      return;
    }
    if (message.header.type != MessageType.testDatabaseConnectionRequest) {
      return;
    }

    final requestId = message.header.requestId;
    final payload = message.payload;

    // Defesa F0.4 / F0.6: tipos errados ou faltando -> 400 invalidRequest
    final databaseTypeRaw = payload['databaseType'];
    if (databaseTypeRaw is! String) {
      await SocketErrorSender.sendProtocolError(
        clientId: clientId,
        requestId: requestId,
        errorMessage: 'Campo `databaseType` ausente ou nao-string',
        sendToClient: sendToClient,
        errorCode: ErrorCode.invalidRequest,
      );
      return;
    }
    final databaseType = RemoteDatabaseType.fromWire(databaseTypeRaw);
    if (databaseType == null) {
      await SocketErrorSender.sendProtocolError(
        clientId: clientId,
        requestId: requestId,
        errorMessage: '`databaseType` nao suportado: $databaseTypeRaw',
        sendToClient: sendToClient,
        errorCode: ErrorCode.invalidRequest,
      );
      return;
    }
    if (await _rejectFirebirdIfUnsupported(
      clientId,
      requestId,
      databaseType,
      sendToClient,
    )) {
      return;
    }

    final hasId =
        payload['databaseConfigId'] is String &&
        (payload['databaseConfigId'] as String).isNotEmpty;
    final hasConfig = payload['config'] is Map;
    if (hasId == hasConfig) {
      // Ambos ou nenhum -> contrato violado
      await SocketErrorSender.sendProtocolError(
        clientId: clientId,
        requestId: requestId,
        errorMessage:
            'Informe APENAS um de `databaseConfigId` ou `config` (XOR)',
        sendToClient: sendToClient,
        errorCode: ErrorCode.invalidRequest,
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

  // ---------------------------------------------------------------
  // CRUD remoto (PR-2)
  // ---------------------------------------------------------------

  Future<void> _handleList(
    String clientId,
    Message message,
    Future<void> Function(String, Message) sendToClient,
  ) async {
    final requestId = message.header.requestId;
    final typeRaw = message.payload['databaseType'];
    if (typeRaw is! String) {
      await SocketErrorSender.sendProtocolError(
        clientId: clientId,
        requestId: requestId,
        errorMessage: '`databaseType` ausente ou nao-string',
        sendToClient: sendToClient,
        errorCode: ErrorCode.invalidRequest,
      );
      return;
    }
    final type = RemoteDatabaseType.fromWire(typeRaw);
    if (type == null) {
      await SocketErrorSender.sendProtocolError(
        clientId: clientId,
        requestId: requestId,
        errorMessage: '`databaseType` nao suportado: $typeRaw',
        sendToClient: sendToClient,
        errorCode: ErrorCode.invalidRequest,
      );
      return;
    }
    if (await _rejectFirebirdIfUnsupported(
      clientId,
      requestId,
      type,
      sendToClient,
    )) {
      return;
    }

    DatabaseConfigOutcome outcome;
    try {
      outcome = await _store.list(type);
    } on Object catch (e, st) {
      LoggerService.warning(
        'DatabaseConfigMessageHandler: list threw for ${type.wireName}: $e',
        e,
        st,
      );
      outcome = DatabaseConfigOutcome.failure(
        error: 'Erro interno: $e',
        errorCode: ErrorCode.unknown,
      );
    }

    if (!outcome.success) {
      await SocketErrorSender.sendProtocolError(
        clientId: clientId,
        requestId: requestId,
        errorMessage: outcome.error ?? 'Falha ao listar configs',
        sendToClient: sendToClient,
        errorCode: outcome.errorCode ?? ErrorCode.unknown,
      );
      return;
    }

    await sendToClient(
      clientId,
      createListDatabaseConfigsResponse(
        requestId: requestId,
        databaseType: type,
        configs: outcome.configs ?? const [],
        serverTimeUtc: _clock(),
      ),
    );
  }

  Future<void> _handleMutation(
    String clientId,
    Message message,
    Future<void> Function(String, Message) sendToClient,
  ) async {
    final requestId = message.header.requestId;
    final type = message.header.type;
    final payload = message.payload;

    final dbTypeRaw = payload['databaseType'];
    if (dbTypeRaw is! String) {
      await SocketErrorSender.sendProtocolError(
        clientId: clientId,
        requestId: requestId,
        errorMessage: '`databaseType` ausente ou nao-string',
        sendToClient: sendToClient,
        errorCode: ErrorCode.invalidRequest,
      );
      return;
    }
    final dbType = RemoteDatabaseType.fromWire(dbTypeRaw);
    if (dbType == null) {
      await SocketErrorSender.sendProtocolError(
        clientId: clientId,
        requestId: requestId,
        errorMessage: '`databaseType` nao suportado: $dbTypeRaw',
        sendToClient: sendToClient,
        errorCode: ErrorCode.invalidRequest,
      );
      return;
    }
    if (await _rejectFirebirdIfUnsupported(
      clientId,
      requestId,
      dbType,
      sendToClient,
    )) {
      return;
    }

    final keyError = IdempotencyPolicy.missingKeyErrorMessage(
      message: message,
      operationType: type,
    );
    if (keyError != null) {
      await sendToClient(clientId, keyError);
      return;
    }

    final idempotencyKey = getIdempotencyKey(message);

    try {
      final response = await _idempotencyRegistry.runIdempotent<Message>(
        key: idempotencyKey,
        compute: () => _doMutation(type, requestId, dbType, payload),
      );
      await sendToClient(clientId, response);
    } on _DbConfigFailure catch (f) {
      await SocketErrorSender.sendProtocolError(
        clientId: clientId,
        requestId: requestId,
        errorMessage: f.message,
        sendToClient: sendToClient,
        errorCode: f.errorCode,
      );
    } on Object catch (e, st) {
      LoggerService.warning(
        'DatabaseConfigMessageHandler: mutation threw: $e',
        e,
        st,
      );
      await SocketErrorSender.sendProtocolError(
        clientId: clientId,
        requestId: requestId,
        errorMessage: 'Erro interno: $e',
        sendToClient: sendToClient,
        errorCode: ErrorCode.unknown,
      );
    }
  }

  Future<Message> _doMutation(
    MessageType type,
    int requestId,
    RemoteDatabaseType dbType,
    Map<String, dynamic> payload,
  ) async {
    switch (type) {
      case MessageType.createDatabaseConfigRequest:
        return _doCreate(requestId, dbType, payload);
      case MessageType.updateDatabaseConfigRequest:
        return _doUpdate(requestId, dbType, payload);
      case MessageType.deleteDatabaseConfigRequest:
        return _doDelete(requestId, dbType, payload);
      default:
        throw const _DbConfigFailure(
          'Tipo de mutacao desconhecido',
          ErrorCode.invalidRequest,
        );
    }
  }

  Future<Message> _doCreate(
    int requestId,
    RemoteDatabaseType type,
    Map<String, dynamic> payload,
  ) async {
    final raw = payload['config'];
    if (raw is! Map) {
      throw const _DbConfigFailure(
        '`config` ausente ou nao-map',
        ErrorCode.invalidRequest,
      );
    }
    final config = Map<String, dynamic>.from(raw);
    final outcome = await _store.create(type, config);
    if (!outcome.success) {
      throw _DbConfigFailure(
        outcome.error ?? 'Falha ao criar config',
        outcome.errorCode ?? ErrorCode.unknown,
      );
    }
    final created = outcome.config ?? config;
    return createDatabaseConfigMutationResponse(
      requestId: requestId,
      operation: 'created',
      databaseType: type,
      configId: created['id'] is String ? created['id'] as String : '',
      config: created,
    );
  }

  Future<Message> _doUpdate(
    int requestId,
    RemoteDatabaseType type,
    Map<String, dynamic> payload,
  ) async {
    final raw = payload['config'];
    if (raw is! Map) {
      throw const _DbConfigFailure(
        '`config` ausente ou nao-map',
        ErrorCode.invalidRequest,
      );
    }
    final config = Map<String, dynamic>.from(raw);
    final id = config['id'] is String ? config['id'] as String : '';
    if (id.isEmpty) {
      throw const _DbConfigFailure(
        'config.id obrigatorio para update',
        ErrorCode.invalidRequest,
      );
    }
    final outcome = await _store.update(type, config);
    if (!outcome.success) {
      throw _DbConfigFailure(
        outcome.error ?? 'Falha ao atualizar config',
        outcome.errorCode ?? ErrorCode.unknown,
      );
    }
    final updated = outcome.config ?? config;
    return createDatabaseConfigMutationResponse(
      requestId: requestId,
      operation: 'updated',
      databaseType: type,
      configId: id,
      config: updated,
    );
  }

  Future<Message> _doDelete(
    int requestId,
    RemoteDatabaseType type,
    Map<String, dynamic> payload,
  ) async {
    final id = payload['configId'] is String
        ? payload['configId'] as String
        : '';
    if (id.isEmpty) {
      throw const _DbConfigFailure(
        'configId vazio',
        ErrorCode.invalidRequest,
      );
    }
    final outcome = await _store.delete(type, id);
    if (!outcome.success) {
      throw _DbConfigFailure(
        outcome.error ?? 'Falha ao deletar config',
        outcome.errorCode ?? ErrorCode.unknown,
      );
    }
    return createDatabaseConfigMutationResponse(
      requestId: requestId,
      operation: 'deleted',
      databaseType: type,
      configId: id,
    );
  }

  Future<bool> _rejectFirebirdIfUnsupported(
    String clientId,
    int requestId,
    RemoteDatabaseType databaseType,
    Future<void> Function(String, Message) sendToClient,
  ) async {
    if (_supportsFirebird || databaseType != RemoteDatabaseType.firebird) {
      return false;
    }
    await SocketErrorSender.sendProtocolError(
      clientId: clientId,
      requestId: requestId,
      errorMessage: ErrorCode.unsupportedDatabaseType.defaultMessage,
      sendToClient: sendToClient,
      errorCode: ErrorCode.unsupportedDatabaseType,
    );
    return true;
  }
}

/// Excecao interna para sair cedo do compute do registry sem cachear
/// erro de validacao/dominio.
class _DbConfigFailure implements Exception {
  const _DbConfigFailure(this.message, this.errorCode);
  final String message;
  final ErrorCode errorCode;
}
