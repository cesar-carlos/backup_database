import 'package:backup_database/application/services/metrics_collector.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_telemetry.dart';
import 'package:backup_database/infrastructure/socket/server/socket_telemetry_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SocketServerTelemetry', () {
    test('records duration histogram and mutable command audit on success', () {
      final metrics = MetricsCollector();
      final clock = _FakeClock(DateTime.utc(2026, 4, 19, 12));
      final telemetry = SocketServerTelemetry(
        metricsCollector: metrics,
        clock: clock.tick,
      );

      final request = createStartBackupRequest(
        scheduleId: 'sch-1',
        idempotencyKey: 'idem-1',
        requestId: 7,
      );
      telemetry.onRequestReceived('client-a', request);
      clock.advance(const Duration(milliseconds: 42));

      final response = createStartBackupResponse(
        requestId: 7,
        runId: 'sch-1_uuid',
        state: ExecutionState.running,
        scheduleId: 'sch-1',
        serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
      );
      telemetry.onResponseSent('client-a', response);

      final durationKey = SocketTelemetryMetrics.requestDurationMs(
        MessageType.startBackupRequest.name,
      );
      final snapshot = metrics.getSnapshot();
      expect(snapshot['${durationKey}_count'], 1);
      expect(snapshot['${durationKey}_sum'], 42);

      final audits = telemetry.recentMutableAudits();
      expect(audits, hasLength(1));
      expect(audits.single.commandType, MessageType.startBackupRequest.name);
      expect(audits.single.idempotencyKey, 'idem-1');
      expect(audits.single.runId, 'sch-1_uuid');
      expect(audits.single.result, 'success');
      expect(audits.single.durationMs, 42);
    });

    test('increments socket_error_total on error response', () {
      final metrics = MetricsCollector();
      final telemetry = SocketServerTelemetry(metricsCollector: metrics);

      telemetry.onRequestReceived(
        'c1',
        createStartBackupRequest(
          scheduleId: 'sch-1',
          idempotencyKey: 'idem-2',
          requestId: 3,
        ),
      );
      telemetry.onResponseSent(
        'c1',
        createErrorMessage(
          requestId: 3,
          errorMessage: ErrorCode.rateLimitExceeded.defaultMessage,
          errorCode: ErrorCode.rateLimitExceeded,
          retryAfterSeconds: 1,
        ),
      );

      final snapshot = metrics.getSnapshot();
      expect(
        snapshot[SocketTelemetryMetrics.errorTotal(
          ErrorCode.rateLimitExceeded.name,
        )],
        1,
      );
      expect(telemetry.recentMutableAudits().single.result, 'error:rateLimitExceeded');
    });

    test('clearClient drops pending requests', () {
      final metrics = MetricsCollector();
      final telemetry = SocketServerTelemetry(metricsCollector: metrics);

      telemetry.onRequestReceived(
        'c1',
        createStartBackupRequest(
          scheduleId: 'sch-1',
          idempotencyKey: 'idem-3',
          requestId: 9,
        ),
      );
      telemetry.clearClient('c1');
      telemetry.onResponseSent(
        'c1',
        createStartBackupResponse(
          requestId: 9,
          runId: 'run-1',
          state: ExecutionState.running,
          scheduleId: 'sch-1',
          serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
        ),
      );

      expect(metrics.getSnapshot(), isEmpty);
    });
  });
}

class _FakeClock {
  _FakeClock(this._now);

  DateTime _now;

  DateTime tick() => _now;

  void advance(Duration delta) {
    _now = _now.add(delta);
  }
}
