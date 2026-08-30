import 'package:backup_database/infrastructure/protocol/diagnostics_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/metrics_messages.dart';
import 'package:backup_database/infrastructure/socket/client/client_rpc_transport.dart';
import 'package:result_dart/result_dart.dart' as rd;

class RemoteDiagnosticsRpc {
  RemoteDiagnosticsRpc({
    required this._rpc,
    required this._isConnected,
    required this._send,
  });

  final ClientRpcTransport _rpc;
  final bool Function() _isConnected;
  final Future<void> Function(Message message) _send;

  Future<rd.Result<RunLogsResult>> getRunLogs({
    required String runId,
    int? maxLines,
  }) {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createGetRunLogsRequest(
        runId: runId,
        maxLines: maxLines,
        requestId: requestId,
      ),
      isExpected: (message) =>
          message.header.type == MessageType.getRunLogsResponse,
      parse: readRunLogsResponse,
      operationName: 'getRunLogs',
      unexpectedLabel: 'getRunLogs',
    );
  }

  Future<rd.Result<RunErrorDetailsResult>> getRunErrorDetails({
    required String runId,
  }) {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createGetRunErrorDetailsRequest(
        runId: runId,
        requestId: requestId,
      ),
      isExpected: (message) =>
          message.header.type == MessageType.getRunErrorDetailsResponse,
      parse: readRunErrorDetailsResponse,
      operationName: 'getRunErrorDetails',
      unexpectedLabel: 'getRunErrorDetails',
    );
  }

  Future<rd.Result<ArtifactMetadataResult>> getArtifactMetadata({
    required String runId,
  }) {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createGetArtifactMetadataRequest(
        runId: runId,
        requestId: requestId,
      ),
      isExpected: (message) =>
          message.header.type == MessageType.getArtifactMetadataResponse,
      parse: readArtifactMetadataResponse,
      operationName: 'getArtifactMetadata',
      unexpectedLabel: 'getArtifactMetadata',
    );
  }

  Future<rd.Result<CleanupStagingResult>> cleanupRemoteStaging({
    required String runId,
    String? idempotencyKey,
  }) {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createCleanupStagingRequest(
        runId: runId,
        idempotencyKey: idempotencyKey,
        requestId: requestId,
      ),
      isExpected: (message) =>
          message.header.type == MessageType.cleanupStagingResponse,
      parse: readCleanupStagingResponse,
      operationName: 'cleanupStaging',
      unexpectedLabel: 'cleanupStaging',
    );
  }

  Future<rd.Result<Map<String, dynamic>>> getServerMetrics() {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createMetricsRequestMessage(requestId: requestId),
      isExpected: (message) =>
          message.header.type == MessageType.metricsResponse,
      parse: getMetricsFromPayload,
      operationName: 'getServerMetrics',
    );
  }
}
