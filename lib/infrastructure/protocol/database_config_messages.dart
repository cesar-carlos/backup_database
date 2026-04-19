import 'dart:convert';

import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/response_envelope.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';

/// Tipos de banco suportados na sondagem remota. Strings padronizadas
/// no protocolo para nao depender de ordem de enum (wire-compat).
enum RemoteDatabaseType {
  sybase('sybase'),
  sqlServer('sqlServer'),
  postgres('postgres');

  final String wireName;
  const RemoteDatabaseType(this.wireName);

  static RemoteDatabaseType? fromWire(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final t in values) {
      if (t.wireName == raw) return t;
    }
    return null;
  }
}

/// Cria uma requisicao de teste de conexao com banco de dados.
///
/// Existem dois modos de uso:
///
/// 1. **Por id persistido** (`databaseConfigId`): cliente solicita que
///    o servidor sonde a conexao com uma config ja salva no servidor
///    (ex.: Sybase Config X). Garante que credenciais nao trafegam
///    pelo socket nesse caso.
/// 2. **Ad-hoc** (`config` map): cliente envia uma config completa no
///    payload — usado em telas de "criar nova config" antes de
///    persistir. O conteudo do `config` e opaco no protocolo
///    (validado pelo handler com base em `databaseType`).
///
/// `timeoutMs` opcional (default servidor) controla o limite maximo
/// que o servidor espera pela resposta do banco.
Message createTestDatabaseConnectionRequest({
  required RemoteDatabaseType databaseType,
  String? databaseConfigId,
  Map<String, dynamic>? config,
  int? timeoutMs,
  int requestId = 0,
}) {
  if (databaseConfigId == null && config == null) {
    throw ArgumentError(
      'testDatabaseConnection: informe `databaseConfigId` OU `config`',
    );
  }
  if (databaseConfigId != null && config != null) {
    throw ArgumentError(
      'testDatabaseConnection: informe APENAS um de `databaseConfigId` ou `config`',
    );
  }

  final payload = <String, dynamic>{
    'databaseType': databaseType.wireName,
    ...?(databaseConfigId != null ? {'databaseConfigId': databaseConfigId} : null),
    ...?(config != null ? {'config': config} : null),
    ...?(timeoutMs != null ? {'timeoutMs': timeoutMs} : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.testDatabaseConnectionRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Cria uma resposta de teste de conexao.
///
/// Quando [connected] for `true`, [errorCode]/[error] sao opcionais.
/// Quando `false`, [errorCode] descreve a categoria do erro (ex.:
/// `AUTH_FAILED`, `IO_ERROR`, `TIMEOUT`).
///
/// O `statusCode` retornado segue a politica F0.5/F0.6:
/// - sucesso (connected=true) -> 200
/// - falha por requisicao malformada -> 400 (mapeado de `errorCode`)
/// - falha por credencial/permissao -> 401/403
/// - falha por banco offline/timeout -> 503/408
///
/// O envelope (`success`/`statusCode`) e aplicado tanto no caso
/// "sucesso de comunicacao mas falha de sondagem" quanto no caso
/// "sucesso de sondagem". O fato de a SONDAGEM ter falhado e expresso
/// em `connected: false`, nao em `success`. `success: true` indica
/// apenas que a request foi processada (vs erro 5xx do servidor).
Message createTestDatabaseConnectionResponse({
  required int requestId,
  required bool connected,
  required int latencyMs,
  required DateTime serverTimeUtc,
  String? error,
  ErrorCode? errorCode,
  Map<String, dynamic>? details,
}) {
  final base = <String, dynamic>{
    'connected': connected,
    'latencyMs': latencyMs,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
    ...?(error != null ? {'error': error} : null),
    ...?(errorCode != null ? {'errorCode': errorCode.code} : null),
    ...?(details != null && details.isNotEmpty
        ? {'details': details}
        : null),
  };

  final statusCode = connected
      ? StatusCodes.ok
      : (errorCode != null
          ? StatusCodes.forErrorCode(errorCode)
          : StatusCodes.serviceUnavailable);

  final payload = wrapSuccessResponse(base, statusCode: statusCode);
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.testDatabaseConnectionResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Snapshot tipado da resposta de teste de conexao, util para exposicao
/// no `ConnectionManager` e UI.
class TestDatabaseConnectionResult {
  const TestDatabaseConnectionResult({
    required this.connected,
    required this.latencyMs,
    required this.serverTimeUtc,
    this.error,
    this.errorCode,
    this.details,
  });

  final bool connected;
  final int latencyMs;
  final DateTime serverTimeUtc;
  final String? error;
  final ErrorCode? errorCode;
  final Map<String, dynamic>? details;

  bool get isSuccess => connected;
  bool get isFailure => !connected;
}

/// Le um [TestDatabaseConnectionResult] do payload da resposta. Tolera
/// servidor `v1` (sem alguns campos) preenchendo defaults seguros.
// ---------------------------------------------------------------------------
// Database CRUD remoto (PR-2)
// ---------------------------------------------------------------------------

/// `listDatabaseConfigs`: cliente solicita todas as configs de um
/// tipo. Resposta inclui lista de Map opacos (cliente interpreta com
/// base no `databaseType` que pediu).
Message createListDatabaseConfigsRequest({
  required RemoteDatabaseType databaseType,
  int requestId = 0,
}) {
  final payload = <String, dynamic>{'databaseType': databaseType.wireName};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.listDatabaseConfigsRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createListDatabaseConfigsResponse({
  required int requestId,
  required RemoteDatabaseType databaseType,
  required List<Map<String, dynamic>> configs,
  required DateTime serverTimeUtc,
}) {
  final base = <String, dynamic>{
    'databaseType': databaseType.wireName,
    'configs': configs,
    'serverTimeUtc': serverTimeUtc.toUtc().toIso8601String(),
  };
  final payload = wrapSuccessResponse(base);
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.listDatabaseConfigsResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Snapshot tipado da resposta de listagem.
class DatabaseConfigListResult {
  const DatabaseConfigListResult({
    required this.databaseType,
    required this.configs,
    required this.serverTimeUtc,
  });

  final RemoteDatabaseType databaseType;
  final List<Map<String, dynamic>> configs;
  final DateTime serverTimeUtc;

  bool get isEmpty => configs.isEmpty;
  int get count => configs.length;
}

DatabaseConfigListResult readDatabaseConfigListResponse(Message message) {
  final p = message.payload;
  final typeRaw = p['databaseType'] is String ? p['databaseType'] as String : '';
  final type = RemoteDatabaseType.fromWire(typeRaw) ?? RemoteDatabaseType.sybase;
  final raw = p['configs'];
  final configs = raw is List
      ? raw
          .whereType<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList()
      : <Map<String, dynamic>>[];
  final serverTimeRaw = p['serverTimeUtc'];
  final serverTime = serverTimeRaw is String
      ? (DateTime.tryParse(serverTimeRaw) ??
          DateTime.fromMillisecondsSinceEpoch(0).toUtc())
      : DateTime.fromMillisecondsSinceEpoch(0).toUtc();
  return DatabaseConfigListResult(
    databaseType: type,
    configs: configs,
    serverTimeUtc: serverTime,
  );
}

/// `createDatabaseConfig` / `updateDatabaseConfig` /
/// `deleteDatabaseConfig`: comandos mutaveis. Aceitam idempotencyKey.
///
/// `config` e um Map opaco — handler concreto (que conhece o tipo)
/// converte para a entity correspondente.
Message createCreateDatabaseConfigRequest({
  required RemoteDatabaseType databaseType,
  required Map<String, dynamic> config,
  String? idempotencyKey,
  int requestId = 0,
}) {
  final payload = <String, dynamic>{
    'databaseType': databaseType.wireName,
    'config': config,
    ...?(idempotencyKey != null && idempotencyKey.isNotEmpty
        ? {'idempotencyKey': idempotencyKey}
        : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.createDatabaseConfigRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createUpdateDatabaseConfigRequest({
  required RemoteDatabaseType databaseType,
  required Map<String, dynamic> config,
  String? idempotencyKey,
  int requestId = 0,
}) {
  final payload = <String, dynamic>{
    'databaseType': databaseType.wireName,
    'config': config,
    ...?(idempotencyKey != null && idempotencyKey.isNotEmpty
        ? {'idempotencyKey': idempotencyKey}
        : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.updateDatabaseConfigRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createDeleteDatabaseConfigRequest({
  required RemoteDatabaseType databaseType,
  required String configId,
  String? idempotencyKey,
  int requestId = 0,
}) {
  final payload = <String, dynamic>{
    'databaseType': databaseType.wireName,
    'configId': configId,
    ...?(idempotencyKey != null && idempotencyKey.isNotEmpty
        ? {'idempotencyKey': idempotencyKey}
        : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.deleteDatabaseConfigRequest,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

/// Resposta unificada de mutacoes de database config.
Message createDatabaseConfigMutationResponse({
  required int requestId,
  required String operation,
  required RemoteDatabaseType databaseType,
  required String configId,
  Map<String, dynamic>? config,
}) {
  final base = <String, dynamic>{
    'operation': operation,
    'databaseType': databaseType.wireName,
    'configId': configId,
    ...?(config != null ? {'config': config} : null),
  };
  final payload = wrapSuccessResponse(base);
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.databaseConfigMutationResponse,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

class DatabaseConfigMutationResult {
  const DatabaseConfigMutationResult({
    required this.operation,
    required this.databaseType,
    required this.configId,
    this.config,
  });

  final String operation;
  final RemoteDatabaseType databaseType;
  final String configId;
  final Map<String, dynamic>? config;

  bool get isCreated => operation == 'created';
  bool get isUpdated => operation == 'updated';
  bool get isDeleted => operation == 'deleted';
}

DatabaseConfigMutationResult readDatabaseConfigMutationResponse(
  Message message,
) {
  final p = message.payload;
  final operation = p['operation'] is String ? p['operation'] as String : '';
  final typeRaw = p['databaseType'] is String ? p['databaseType'] as String : '';
  final type = RemoteDatabaseType.fromWire(typeRaw) ?? RemoteDatabaseType.sybase;
  final configId = p['configId'] is String ? p['configId'] as String : '';
  final cfg = p['config'] is Map
      ? Map<String, dynamic>.from(p['config'] as Map)
      : null;
  return DatabaseConfigMutationResult(
    operation: operation,
    databaseType: type,
    configId: configId,
    config: cfg,
  );
}

TestDatabaseConnectionResult readTestDatabaseConnectionResponse(
  Message message,
) {
  final p = message.payload;
  final connected = p['connected'] is bool && p['connected'] as bool;
  final latencyMs = p['latencyMs'] is int ? p['latencyMs'] as int : 0;
  final serverTimeRaw = p['serverTimeUtc'];
  final serverTime = serverTimeRaw is String
      ? (DateTime.tryParse(serverTimeRaw) ?? DateTime.fromMillisecondsSinceEpoch(0).toUtc())
      : DateTime.fromMillisecondsSinceEpoch(0).toUtc();
  final error = p['error'] is String ? p['error'] as String : null;
  final errorCodeRaw = p['errorCode'] is String ? p['errorCode'] as String : null;
  final errorCode = errorCodeRaw != null ? ErrorCode.fromString(errorCodeRaw) : null;
  final details = p['details'] is Map ? Map<String, dynamic>.from(p['details'] as Map) : null;

  return TestDatabaseConnectionResult(
    connected: connected,
    latencyMs: latencyMs,
    serverTimeUtc: serverTime,
    error: error,
    errorCode: errorCode,
    details: details,
  );
}
