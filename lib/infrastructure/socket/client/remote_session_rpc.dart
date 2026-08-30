import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/infrastructure/protocol/capabilities_messages.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/health_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/protocol/queue_events.dart';
import 'package:backup_database/infrastructure/protocol/session_messages.dart';
import 'package:backup_database/infrastructure/socket/client/client_rpc_transport.dart';
import 'package:result_dart/result_dart.dart' as rd;

class RemoteSessionRpc {
  RemoteSessionRpc({
    required this._rpc,
    required this._isConnected,
    required this._send,
  });

  final ClientRpcTransport _rpc;
  final bool Function() _isConnected;
  final Future<void> Function(Message message) _send;

  Future<rd.Result<ServerCapabilities>> getServerCapabilities() {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) =>
          createCapabilitiesRequestMessage(requestId: requestId),
      isExpected: isCapabilitiesResponseMessage,
      parse: readCapabilitiesFromResponse,
      operationName: 'getServerCapabilities',
      unexpectedLabel: 'capabilities',
    );
  }

  Future<rd.Result<ServerHealth>> getServerHealth() {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createHealthRequestMessage(requestId: requestId),
      isExpected: isHealthResponseMessage,
      parse: readHealthFromResponse,
      operationName: 'getServerHealth',
      unexpectedLabel: 'health',
    );
  }

  Future<rd.Result<ServerSession>> getServerSession() {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createSessionRequestMessage(requestId: requestId),
      isExpected: isSessionResponseMessage,
      parse: readSessionFromResponse,
      operationName: 'getServerSession',
      unexpectedLabel: 'session',
    );
  }

  Future<rd.Result<PreflightResult>> validateServerBackupPrerequisites() {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createPreflightRequestMessage(requestId: requestId),
      isExpected: isPreflightResponseMessage,
      parse: readPreflightFromResponse,
      operationName: 'validateServerBackupPrerequisites',
      unexpectedLabel: 'preflight',
    );
  }

  Future<rd.Result<ExecutionStatusResult>> getExecutionStatus(String runId) {
    if (runId.isEmpty) {
      return Future.value(rd.Failure(Exception('runId must not be empty')));
    }
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createExecutionStatusRequestMessage(
        requestId: requestId,
        runId: runId,
      ),
      isExpected: isExecutionStatusResponseMessage,
      parse: readExecutionStatusFromResponse,
      operationName: 'getExecutionStatus',
      unexpectedLabel: 'executionStatus',
    );
  }

  Future<rd.Result<ExecutionQueueResult>> getExecutionQueue() {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) =>
          createExecutionQueueRequestMessage(requestId: requestId),
      isExpected: isExecutionQueueResponseMessage,
      parse: readExecutionQueueFromResponse,
      operationName: 'getExecutionQueue',
      unexpectedLabel: 'executionQueue',
    );
  }

  Future<rd.Result<TestDatabaseConnectionResult>> testRemoteDatabaseConnection({
    required RemoteDatabaseType databaseType,
    String? databaseConfigId,
    Map<String, dynamic>? config,
    Duration? timeout,
  }) {
    if (databaseConfigId == null && config == null) {
      return Future.value(
        rd.Failure(
          Exception('testRemoteDatabaseConnection: informe id OU config'),
        ),
      );
    }
    if (databaseConfigId != null && config != null) {
      return Future.value(
        rd.Failure(
          Exception('testRemoteDatabaseConnection: informe APENAS um (XOR)'),
        ),
      );
    }
    final clientTimeout = timeout != null
        ? (timeout + const Duration(seconds: 5))
        : SocketConfig.scheduleRequestTimeout;
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createTestDatabaseConnectionRequest(
        databaseType: databaseType,
        databaseConfigId: databaseConfigId,
        config: config,
        timeoutMs: timeout?.inMilliseconds,
        requestId: requestId,
      ),
      isExpected: (message) =>
          message.header.type == MessageType.testDatabaseConnectionResponse,
      parse: readTestDatabaseConnectionResponse,
      operationName: 'testRemoteDatabaseConnection',
      unexpectedLabel: 'testDatabaseConnection',
      timeout: clientTimeout,
    );
  }

  Future<rd.Result<StartBackupResult>> startRemoteBackup({
    required String scheduleId,
    String? idempotencyKey,
    bool queueIfBusy = false,
  }) {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createStartBackupRequest(
        scheduleId: scheduleId,
        idempotencyKey: idempotencyKey,
        queueIfBusy: queueIfBusy,
        requestId: requestId,
      ),
      isExpected: (message) =>
          message.header.type == MessageType.startBackupResponse,
      parse: readStartBackupResponse,
      operationName: 'startRemoteBackup',
      unexpectedLabel: 'startBackup',
    );
  }

  Future<rd.Result<CancelBackupResult>> cancelRemoteBackup({
    String? runId,
    String? scheduleId,
    String? idempotencyKey,
  }) {
    final hasRun = runId != null && runId.isNotEmpty;
    final hasSch = scheduleId != null && scheduleId.isNotEmpty;
    if (hasRun == hasSch) {
      return Future.value(
        rd.Failure(
          Exception(
            'cancelRemoteBackup: informe APENAS um (runId XOR scheduleId)',
          ),
        ),
      );
    }
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createCancelBackupRequest(
        runId: runId,
        scheduleId: scheduleId,
        idempotencyKey: idempotencyKey,
        requestId: requestId,
      ),
      isExpected: (message) =>
          message.header.type == MessageType.cancelBackupResponse,
      parse: readCancelBackupResponse,
      operationName: 'cancelRemoteBackup',
      unexpectedLabel: 'cancelBackup',
    );
  }

  Future<rd.Result<CancelQueuedBackupResult>> cancelQueuedRemoteBackup({
    required String runId,
    String? idempotencyKey,
  }) {
    if (runId.isEmpty) {
      return Future.value(
        rd.Failure(
          Exception('cancelQueuedRemoteBackup: runId obrigatorio'),
        ),
      );
    }
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createCancelQueuedBackupRequest(
        runId: runId,
        idempotencyKey: idempotencyKey,
        requestId: requestId,
      ),
      isExpected: (message) =>
          message.header.type == MessageType.cancelQueuedBackupResponse,
      parse: readCancelQueuedBackupResponse,
      operationName: 'cancelQueuedRemoteBackup',
      unexpectedLabel: 'cancelQueuedBackup',
    );
  }
}
