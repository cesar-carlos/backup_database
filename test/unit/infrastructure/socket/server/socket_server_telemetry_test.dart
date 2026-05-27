import 'package:backup_database/application/services/metrics_collector.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
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
      expect(
        telemetry.recentMutableAudits().single.result,
        'error:rateLimitExceeded',
      );
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

    test('PR-6: persiste audit em DB quando dao injetado', () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final telemetry = SocketServerTelemetry(
        metricsCollector: MetricsCollector(),
        auditDao: db.mutableCommandAuditDao,
      );

      telemetry.onRequestReceived(
        'client-persist',
        createStartBackupRequest(
          scheduleId: 'sch-1',
          idempotencyKey: 'idem-persist',
          requestId: 42,
        ),
      );
      telemetry.onResponseSent(
        'client-persist',
        createStartBackupResponse(
          requestId: 42,
          runId: 'sch-1_run',
          state: ExecutionState.running,
          scheduleId: 'sch-1',
          serverTimeUtc: DateTime.utc(2026, 5, 27, 12),
        ),
      );

      // best-effort persist e async — espera o microtask.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final rows = await db.mutableCommandAuditDao.recentAudits();
      expect(rows, hasLength(1));
      expect(rows.first.commandType, MessageType.startBackupRequest.name);
      expect(rows.first.clientId, 'client-persist');
      expect(rows.first.idempotencyKey, 'idem-persist');
      expect(rows.first.runId, 'sch-1_run');
      expect(rows.first.result, 'success');
    });

    test('PR-6: deleteOlderThan remove apenas registros antigos', () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final dao = db.mutableCommandAuditDao;

      final old = DateTime.utc(2025);
      final fresh = DateTime.utc(2026, 5, 27);
      await dao.insertAudit(
        id: 'a-old',
        clientId: 'c',
        commandType: 'startBackupRequest',
        result: 'success',
        timestampUtc: old,
      );
      await dao.insertAudit(
        id: 'a-fresh',
        clientId: 'c',
        commandType: 'startBackupRequest',
        result: 'success',
        timestampUtc: fresh,
      );

      final cutoff = DateTime.utc(2025, 6);
      final deleted = await dao.deleteOlderThan(cutoff);
      expect(deleted, 1);

      final rows = await dao.recentAudits();
      expect(rows.map((r) => r.id), ['a-fresh']);
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
