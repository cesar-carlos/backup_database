import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/client/client_rpc_transport.dart';
import 'package:result_dart/result_dart.dart' as rd;

class RemoteDatabaseConfigRpc {
  RemoteDatabaseConfigRpc({
    required this._rpc,
    required this._isConnected,
    required this._send,
  });

  final ClientRpcTransport _rpc;
  final bool Function() _isConnected;
  final Future<void> Function(Message message) _send;

  Future<rd.Result<DatabaseConfigListResult>> listRemoteDatabaseConfigs(
    RemoteDatabaseType databaseType,
  ) {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createListDatabaseConfigsRequest(
        databaseType: databaseType,
        requestId: requestId,
      ),
      isExpected: (message) =>
          message.header.type == MessageType.listDatabaseConfigsResponse,
      parse: readDatabaseConfigListResponse,
      operationName: 'listRemoteDatabaseConfigs',
      unexpectedLabel: 'listDatabaseConfigs',
    );
  }

  Future<rd.Result<DatabaseConfigMutationResult>> createRemoteDatabaseConfig({
    required RemoteDatabaseType databaseType,
    required Map<String, dynamic> config,
    String? idempotencyKey,
  }) {
    return _runMutation(
      (requestId) => createCreateDatabaseConfigRequest(
        databaseType: databaseType,
        config: config,
        idempotencyKey: idempotencyKey,
        requestId: requestId,
      ),
      operationName: 'createDatabaseConfig',
    );
  }

  Future<rd.Result<DatabaseConfigMutationResult>> updateRemoteDatabaseConfig({
    required RemoteDatabaseType databaseType,
    required Map<String, dynamic> config,
    String? idempotencyKey,
  }) {
    return _runMutation(
      (requestId) => createUpdateDatabaseConfigRequest(
        databaseType: databaseType,
        config: config,
        idempotencyKey: idempotencyKey,
        requestId: requestId,
      ),
      operationName: 'updateDatabaseConfig',
    );
  }

  Future<rd.Result<DatabaseConfigMutationResult>> deleteRemoteDatabaseConfig({
    required RemoteDatabaseType databaseType,
    required String configId,
    String? idempotencyKey,
  }) {
    return _runMutation(
      (requestId) => createDeleteDatabaseConfigRequest(
        databaseType: databaseType,
        configId: configId,
        idempotencyKey: idempotencyKey,
        requestId: requestId,
      ),
      operationName: 'deleteDatabaseConfig',
    );
  }

  Future<rd.Result<DatabaseConfigMutationResult>> _runMutation(
    Message Function(int requestId) build, {
    required String operationName,
  }) {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: build,
      isExpected: (message) =>
          message.header.type == MessageType.databaseConfigMutationResponse,
      parse: readDatabaseConfigMutationResponse,
      operationName: operationName,
      unexpectedLabel: operationName,
    );
  }
}
