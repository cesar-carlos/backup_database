import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Preflight messages (F1.8 / PR-1)', () {
    test('createPreflightRequestMessage tem payload vazio', () {
      final msg = createPreflightRequestMessage(requestId: 1);
      expect(msg.header.type, MessageType.preflightRequest);
      expect(msg.payload, isEmpty);
      expect(isPreflightRequestMessage(msg), isTrue);
    });

    test('createPreflightResponseMessage carrega checks + status', () {
      final clock = DateTime.utc(2026, 4, 19, 12);
      final msg = createPreflightResponseMessage(
        requestId: 2,
        status: PreflightStatus.passed,
        checks: const [
          PreflightCheckResult(
            name: 'compression_tool',
            passed: true,
            severity: PreflightSeverity.blocking,
            message: 'WinRAR detectado em PATH',
          ),
        ],
        serverTimeUtc: clock,
      );

      expect(msg.header.type, MessageType.preflightResponse);
      expect(msg.payload['status'], 'passed');
      expect((msg.payload['checks'] as List).length, 1);
      expect(msg.payload['serverTimeUtc'], '2026-04-19T12:00:00.000Z');
      expect(msg.payload.containsKey('message'), isFalse);
    });

    test('readPreflightFromResponse retorna snapshot tipado', () {
      final msg = createPreflightResponseMessage(
        requestId: 1,
        status: PreflightStatus.passedWithWarnings,
        checks: const [
          PreflightCheckResult(
            name: 'compression_tool',
            passed: true,
            severity: PreflightSeverity.blocking,
            message: 'OK',
          ),
          PreflightCheckResult(
            name: 'disk_space',
            passed: false,
            severity: PreflightSeverity.warning,
            message: 'Apenas 5GB livres',
            details: {'freeBytes': 5368709120},
          ),
        ],
        serverTimeUtc: DateTime.utc(2026, 4, 19, 10),
        message: 'Avisos: disk_space',
      );

      final result = readPreflightFromResponse(msg);
      expect(result.status, PreflightStatus.passedWithWarnings);
      expect(result.isOk, isTrue);
      expect(result.hasWarnings, isTrue);
      expect(result.isBlocked, isFalse);
      expect(result.checks.length, 2);
      expect(result.warnings.length, 1);
      expect(result.warnings.first.name, 'disk_space');
      expect(result.warnings.first.details['freeBytes'], 5368709120);
      expect(result.blockingFailures, isEmpty);
      expect(result.message, 'Avisos: disk_space');
    });

    test(
      'readPreflightFromResponse aplica defaults defensivos em payload vazio',
      () {
        final msg = Message(
          header: MessageHeader(
            type: MessageType.preflightResponse,
            length: 0,
            requestId: 1,
          ),
          payload: const <String, dynamic>{},
          checksum: 0,
        );

        final result = readPreflightFromResponse(msg);
        // status ausente -> blocked (fail-closed)
        expect(result.status, PreflightStatus.blocked);
        expect(result.isOk, isFalse);
        expect(result.isBlocked, isTrue);
        expect(result.checks, isEmpty);
        expect(result.serverTimeUtc.isUtc, isTrue);
      },
    );

    test('PreflightStatus.fromString tolera valor invalido', () {
      expect(
        PreflightStatus.fromString('passed'),
        PreflightStatus.passed,
      );
      expect(
        PreflightStatus.fromString('passedWithWarnings'),
        PreflightStatus.passedWithWarnings,
      );
      expect(
        PreflightStatus.fromString('blocked'),
        PreflightStatus.blocked,
      );
      // Valor inesperado -> fail-closed
      expect(
        PreflightStatus.fromString('xyz'),
        PreflightStatus.blocked,
      );
    });

    test('PreflightSeverity.fromString tolera valor invalido', () {
      expect(
        PreflightSeverity.fromString('blocking'),
        PreflightSeverity.blocking,
      );
      expect(
        PreflightSeverity.fromString('warning'),
        PreflightSeverity.warning,
      );
      expect(
        PreflightSeverity.fromString('info'),
        PreflightSeverity.info,
      );
      // Valor inesperado -> info (nao escala arbitrariamente)
      expect(
        PreflightSeverity.fromString('xyz'),
        PreflightSeverity.info,
      );
    });

    test('blocked status com bloqueante e warning juntos', () {
      final msg = createPreflightResponseMessage(
        requestId: 1,
        status: PreflightStatus.blocked,
        checks: const [
          PreflightCheckResult(
            name: 'compression_tool',
            passed: false,
            severity: PreflightSeverity.blocking,
            message: 'WinRAR nao encontrado',
          ),
          PreflightCheckResult(
            name: 'disk_space',
            passed: false,
            severity: PreflightSeverity.warning,
            message: 'Pouco espaco',
          ),
        ],
        serverTimeUtc: DateTime.utc(2026),
        message: 'Bloqueado: compression_tool, disk_space',
      );

      final result = readPreflightFromResponse(msg);
      expect(result.isBlocked, isTrue);
      expect(result.blockingFailures.length, 1);
      expect(result.blockingFailures.first.name, 'compression_tool');
      expect(result.warnings.length, 1);
      expect(result.warnings.first.name, 'disk_space');
    });

    test('serverTimeUtc e sempre serializado em ISO 8601 UTC', () {
      final localTime = DateTime(2026, 4, 19, 9, 30); // local
      final msg = createPreflightResponseMessage(
        requestId: 1,
        status: PreflightStatus.passed,
        checks: const [],
        serverTimeUtc: localTime,
      );

      final raw = msg.payload['serverTimeUtc'] as String;
      expect(raw.endsWith('Z'), isTrue);
      final parsed = DateTime.parse(raw);
      expect(parsed.isUtc, isTrue);
    });

    test('PreflightCheckResult.toMap omite details quando vazio', () {
      const r = PreflightCheckResult(
        name: 'x',
        passed: true,
        severity: PreflightSeverity.info,
        message: 'msg',
      );
      final map = r.toMap();
      expect(map.containsKey('details'), isFalse);

      const r2 = PreflightCheckResult(
        name: 'y',
        passed: false,
        severity: PreflightSeverity.warning,
        message: 'msg',
        details: {'key': 'value'},
      );
      final map2 = r2.toMap();
      expect(map2['details'], {'key': 'value'});
    });
  });
}
