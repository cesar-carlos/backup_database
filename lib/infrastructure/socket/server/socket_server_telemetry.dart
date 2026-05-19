import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_registry.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/server/socket_rate_limiter.dart';
import 'package:backup_database/infrastructure/socket/server/socket_telemetry_constants.dart';

class SocketMutableCommandAuditEntry {
  const SocketMutableCommandAuditEntry({
    required this.clientId,
    required this.commandType,
    required this.timestampUtc,
    required this.result,
    this.requestId,
    this.runId,
    this.idempotencyKey,
    this.durationMs,
  });

  final String clientId;
  final String commandType;
  final DateTime timestampUtc;
  final String result;
  final int? requestId;
  final String? runId;
  final String? idempotencyKey;
  final int? durationMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'clientId': clientId,
    'commandType': commandType,
    'timestampUtc': timestampUtc.toUtc().toIso8601String(),
    'result': result,
    if (requestId != null) 'requestId': requestId,
    if (runId != null && runId!.isNotEmpty) 'runId': runId,
    if (idempotencyKey != null && idempotencyKey!.isNotEmpty)
      'idempotencyKey': idempotencyKey,
    if (durationMs != null) 'durationMs': durationMs,
  };
}

class _PendingSocketRequest {
  _PendingSocketRequest({
    required this.messageType,
    required this.receivedAt,
    this.idempotencyKey,
    this.runIdHint,
  });

  final MessageType messageType;
  final DateTime receivedAt;
  final String? idempotencyKey;
  final String? runIdHint;
}

/// Telemetria M7.1 (`socket_request_duration_*`, `socket_error_total_*`)
/// e audit estruturado M5.2 para comandos mutaveis no socket servidor.
class SocketServerTelemetry {
  SocketServerTelemetry({
    IMetricsCollector? metricsCollector,
    DateTime Function()? clock,
  }) : _metricsCollector = metricsCollector,
       _clock = clock ?? DateTime.now;

  final IMetricsCollector? _metricsCollector;
  final DateTime Function() _clock;

  final Map<String, _PendingSocketRequest> _pendingByKey =
      <String, _PendingSocketRequest>{};
  final List<SocketMutableCommandAuditEntry> _recentMutableAudits =
      <SocketMutableCommandAuditEntry>[];

  static const Set<MessageType> _skipDurationTypes = <MessageType>{
    MessageType.heartbeat,
    MessageType.disconnect,
    MessageType.authRequest,
    MessageType.authResponse,
    MessageType.authChallenge,
    MessageType.error,
  };

  void onRequestReceived(String clientId, Message message) {
    _pruneStalePending();
    final type = message.header.type;
    if (_skipDurationTypes.contains(type)) {
      return;
    }
    _pendingByKey[_pendingKey(
      clientId,
      message.header.requestId,
    )] = _PendingSocketRequest(
      messageType: type,
      receivedAt: _clock(),
      idempotencyKey: getIdempotencyKey(message),
      runIdHint: _runIdHintFromPayload(message),
    );
  }

  void onResponseSent(String clientId, Message message) {
    _pruneStalePending();
    final requestId = message.header.requestId;
    final pending = _pendingByKey.remove(_pendingKey(clientId, requestId));

    int? durationMs;
    if (pending != null && !_skipDurationTypes.contains(pending.messageType)) {
      durationMs = _clock().difference(pending.receivedAt).inMilliseconds;
      _metricsCollector?.recordHistogram(
        SocketTelemetryMetrics.requestDurationMs(pending.messageType.name),
        durationMs,
      );
    }

    if (message.header.type == MessageType.error) {
      final code = getErrorCodeFromMessage(message);
      if (code != null) {
        _metricsCollector?.incrementCounter(
          SocketTelemetryMetrics.errorTotal(code.name),
        );
      }
    }

    if (pending != null &&
        SocketRateLimiter.isMutatingMessageType(pending.messageType)) {
      _recordMutableAudit(
        clientId: clientId,
        commandType: pending.messageType.name,
        requestId: requestId,
        idempotencyKey: pending.idempotencyKey,
        runId: _runIdFromResponse(message) ?? pending.runIdHint,
        result: _resultLabel(message),
        durationMs: durationMs,
      );
    }
  }

  void clearClient(String clientId) {
    _pendingByKey.removeWhere((key, _) => key.startsWith('$clientId:'));
  }

  List<SocketMutableCommandAuditEntry> recentMutableAudits() =>
      List<SocketMutableCommandAuditEntry>.unmodifiable(_recentMutableAudits);

  Map<String, dynamic> observabilitySnapshot() => <String, dynamic>{
    if (_recentMutableAudits.isNotEmpty)
      'socketRecentMutableAudits': _recentMutableAudits
          .map((e) => e.toJson())
          .toList(growable: false),
  };

  void _recordMutableAudit({
    required String clientId,
    required String commandType,
    required int requestId,
    required String result,
    String? idempotencyKey,
    String? runId,
    int? durationMs,
  }) {
    final entry = SocketMutableCommandAuditEntry(
      clientId: clientId,
      commandType: commandType,
      timestampUtc: _clock().toUtc(),
      result: result,
      requestId: requestId,
      runId: runId,
      idempotencyKey: idempotencyKey,
      durationMs: durationMs,
    );
    _recentMutableAudits.add(entry);
    if (_recentMutableAudits.length >
        SocketTelemetryLimits.maxRecentMutableAudits) {
      _recentMutableAudits.removeAt(0);
    }
    LoggerService.infoWithContext(
      'socket mutable command audit: $commandType result=$result '
      'idempotencyKey=${idempotencyKey ?? '-'} durationMs=${durationMs ?? '-'}',
      clientId: clientId,
      requestId: requestId.toString(),
      runId: runId,
    );
  }

  void _pruneStalePending() {
    final cutoff = _clock().subtract(SocketTelemetryLimits.pendingRequestTtl);
    _pendingByKey.removeWhere(
      (_, pending) => pending.receivedAt.isBefore(cutoff),
    );
  }

  String _pendingKey(String clientId, int requestId) => '$clientId:$requestId';

  String? _runIdHintFromPayload(Message message) {
    final runId = getRunIdFromBackupMessage(message);
    if (runId != null && runId.isNotEmpty) {
      return runId;
    }
    final raw = message.payload['runId'];
    if (raw is String && raw.isNotEmpty) {
      return raw;
    }
    return null;
  }

  String? _runIdFromResponse(Message message) {
    if (message.header.type == MessageType.startBackupResponse) {
      final raw = message.payload['runId'];
      if (raw is String && raw.isNotEmpty) {
        return raw;
      }
    }
    return _runIdHintFromPayload(message);
  }

  String _resultLabel(Message message) {
    if (message.header.type == MessageType.error) {
      final code = getErrorCodeFromMessage(message);
      return 'error:${code?.name ?? 'unknown'}';
    }
    return 'success';
  }
}
