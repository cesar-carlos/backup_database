import 'package:backup_database/infrastructure/protocol/health_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/utils/staging_usage_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Health messages (M1.10 / PR-1)', () {
    test('createHealthRequestMessage tem payload vazio', () {
      final msg = createHealthRequestMessage(requestId: 1);
      expect(msg.header.type, MessageType.healthRequest);
      expect(msg.payload, isEmpty);
      expect(isHealthRequestMessage(msg), isTrue);
    });

    test('createHealthResponseMessage carrega todos os campos', () {
      final clock = DateTime.utc(2026, 4, 19, 12);
      final msg = createHealthResponseMessage(
        requestId: 2,
        status: ServerHealthStatus.ok,
        checks: const {'socket': true, 'database': true},
        serverTimeUtc: clock,
        uptimeSeconds: 3600,
      );

      expect(msg.header.type, MessageType.healthResponse);
      expect(msg.payload['status'], 'ok');
      expect(msg.payload['checks'], {'socket': true, 'database': true});
      expect(msg.payload['serverTimeUtc'], '2026-04-19T12:00:00.000Z');
      expect(msg.payload['uptimeSeconds'], 3600);
      expect(msg.payload.containsKey('message'), isFalse);
    });

    test('createHealthResponseMessage inclui message quando fornecido', () {
      final msg = createHealthResponseMessage(
        requestId: 1,
        status: ServerHealthStatus.degraded,
        checks: const {'socket': true, 'database': false},
        serverTimeUtc: DateTime.utc(2026, 4, 19),
        uptimeSeconds: 100,
        message: 'database optional check failed',
      );
      expect(msg.payload['message'], 'database optional check failed');
    });

    test('readHealthFromResponse retorna snapshot tipado', () {
      final msg = createHealthResponseMessage(
        requestId: 1,
        status: ServerHealthStatus.ok,
        checks: const {'socket': true, 'database': true},
        serverTimeUtc: DateTime.utc(2026, 4, 19, 10),
        uptimeSeconds: 7200,
      );

      final health = readHealthFromResponse(msg);
      expect(health.status, ServerHealthStatus.ok);
      expect(health.isOk, isTrue);
      expect(health.isDegraded, isFalse);
      expect(health.isUnhealthy, isFalse);
      expect(health.checks['socket'], isTrue);
      expect(health.checks['database'], isTrue);
      expect(health.serverTimeUtc, DateTime.utc(2026, 4, 19, 10));
      expect(health.uptimeSeconds, 7200);
      expect(health.message, isNull);
      expect(health.stagingUsageLevel, isNull);
    });

    test('readHealthFromResponse com staging (PR-4)', () {
      final msg = createHealthResponseMessage(
        requestId: 1,
        status: ServerHealthStatus.degraded,
        checks: const {'socket': true},
        serverTimeUtc: DateTime.utc(2026, 4, 19, 10),
        uptimeSeconds: 0,
        stagingUsageBytes: 6 * 1024 * 1024 * 1024,
        stagingUsageWarnThresholdBytes: StagingUsagePolicy.warnThresholdBytes,
        stagingUsageBlockThresholdBytes: StagingUsagePolicy.blockThresholdBytes,
        stagingUsageLevel: 'warn',
      );
      final health = readHealthFromResponse(msg);
      expect(health.stagingUsageBytes, 6 * 1024 * 1024 * 1024);
      expect(health.stagingUsageWarnThresholdBytes, StagingUsagePolicy.warnThresholdBytes);
      expect(health.stagingUsageBlockThresholdBytes, StagingUsagePolicy.blockThresholdBytes);
      expect(health.stagingUsageLevel, 'warn');
      expect(health.isDegraded, isTrue);
    });

    test('readHealthFromResponse aplica defaults defensivos', () {
      // Payload minimo / payload com campos faltando
      final msg = Message(
        header: MessageHeader(
          type: MessageType.healthResponse,
          length: 0,
          requestId: 1,
        ),
        payload: const <String, dynamic>{},
        checksum: 0,
      );

      final health = readHealthFromResponse(msg);
      // status ausente -> unhealthy (fail-closed)
      expect(health.status, ServerHealthStatus.unhealthy);
      expect(health.checks, isEmpty);
      // serverTimeUtc invalido -> usa clock local (so testamos que e UTC)
      expect(health.serverTimeUtc.isUtc, isTrue);
      expect(health.uptimeSeconds, 0);
    });

    test('ServerHealthStatus.fromString tolera valor invalido', () {
      expect(ServerHealthStatus.fromString('ok'), ServerHealthStatus.ok);
      expect(
        ServerHealthStatus.fromString('degraded'),
        ServerHealthStatus.degraded,
      );
      expect(
        ServerHealthStatus.fromString('unhealthy'),
        ServerHealthStatus.unhealthy,
      );
      // Valor inesperado -> fail-closed (unhealthy)
      expect(
        ServerHealthStatus.fromString('xyz'),
        ServerHealthStatus.unhealthy,
      );
    });

    test('readHealthFromResponse ignora checks com tipos errados', () {
      final msg = Message(
        header: MessageHeader(
          type: MessageType.healthResponse,
          length: 0,
          requestId: 1,
        ),
        payload: const <String, dynamic>{
          'status': 'ok',
          'checks': {
            'socket': true,
            'database': 'yes', // tipo errado, deve ser ignorado
            'staging': false,
          },
          'serverTimeUtc': '2026-04-19T10:00:00Z',
          'uptimeSeconds': 100,
        },
        checksum: 0,
      );

      final health = readHealthFromResponse(msg);
      expect(health.checks['socket'], isTrue);
      expect(health.checks.containsKey('database'), isFalse);
      expect(health.checks['staging'], isFalse);
    });

    test('serverTimeUtc e sempre serializado em ISO 8601 UTC', () {
      final localTime = DateTime(2026, 4, 19, 9, 30); // local
      final msg = createHealthResponseMessage(
        requestId: 1,
        status: ServerHealthStatus.ok,
        checks: const {'socket': true},
        serverTimeUtc: localTime,
        uptimeSeconds: 0,
      );

      final raw = msg.payload['serverTimeUtc'] as String;
      expect(raw.endsWith('Z'), isTrue);
      final parsed = DateTime.parse(raw);
      expect(parsed.isUtc, isTrue);
    });
  });
}
