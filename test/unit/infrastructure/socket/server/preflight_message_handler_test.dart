import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/socket/server/preflight_message_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PreflightMessageHandler', () {
    test(
      'sem checks injetados: responde passed com lista vazia',
      () async {
        final fixedNow = DateTime.utc(2026, 4, 19, 12);
        final handler = PreflightMessageHandler(clock: () => fixedNow);

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'c1',
          createPreflightRequestMessage(),
          capture,
        );

        expect(sent, isNotNull);
        expect(sent!.header.type, MessageType.preflightResponse);
        final result = readPreflightFromResponse(sent!);
        expect(result.status, PreflightStatus.passed);
        expect(result.isOk, isTrue);
        expect(result.checks, isEmpty);
        expect(result.serverTimeUtc, fixedNow);
        expect(result.message, isNull);
      },
    );

    test(
      'todos os checks passam: agregacao = passed',
      () async {
        final handler = PreflightMessageHandler(
          checks: {
            'compression_tool': () async => const PreflightCheckResult(
                  name: 'compression_tool',
                  passed: true,
                  severity: PreflightSeverity.blocking,
                  message: 'WinRAR OK',
                ),
            'disk_space': () async => const PreflightCheckResult(
                  name: 'disk_space',
                  passed: true,
                  severity: PreflightSeverity.warning,
                  message: '50GB livres',
                ),
          },
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createPreflightRequestMessage(), capture);

        final result = readPreflightFromResponse(sent!);
        expect(result.status, PreflightStatus.passed);
        expect(result.checks.length, 2);
        expect(result.message, isNull);
      },
    );

    test(
      'warning falhou (sem blocking): agregacao = passedWithWarnings',
      () async {
        final handler = PreflightMessageHandler(
          checks: {
            'compression_tool': () async => const PreflightCheckResult(
                  name: 'compression_tool',
                  passed: true,
                  severity: PreflightSeverity.blocking,
                  message: 'OK',
                ),
            'disk_space': () async => const PreflightCheckResult(
                  name: 'disk_space',
                  passed: false,
                  severity: PreflightSeverity.warning,
                  message: 'Pouco espaco',
                ),
          },
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createPreflightRequestMessage(), capture);

        final result = readPreflightFromResponse(sent!);
        expect(result.status, PreflightStatus.passedWithWarnings);
        expect(result.warnings.length, 1);
        expect(result.blockingFailures, isEmpty);
        expect(result.message, contains('disk_space'));
      },
    );

    test(
      'blocking falhou (com warning): agregacao = blocked',
      () async {
        final handler = PreflightMessageHandler(
          checks: {
            'compression_tool': () async => const PreflightCheckResult(
                  name: 'compression_tool',
                  passed: false,
                  severity: PreflightSeverity.blocking,
                  message: 'WinRAR nao encontrado',
                ),
            'disk_space': () async => const PreflightCheckResult(
                  name: 'disk_space',
                  passed: false,
                  severity: PreflightSeverity.warning,
                  message: 'Pouco espaco',
                ),
          },
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createPreflightRequestMessage(), capture);

        final result = readPreflightFromResponse(sent!);
        expect(result.status, PreflightStatus.blocked);
        expect(result.blockingFailures.length, 1);
        expect(result.warnings.length, 1);
        expect(result.message, contains('compression_tool'));
      },
    );

    test(
      'check que lanca excecao e tratado como blocking failure (fail-closed)',
      () async {
        final handler = PreflightMessageHandler(
          checks: {
            'database': () async => throw Exception('connection refused'),
          },
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createPreflightRequestMessage(), capture);

        final result = readPreflightFromResponse(sent!);
        expect(result.status, PreflightStatus.blocked);
        expect(result.blockingFailures.length, 1);
        expect(result.blockingFailures.first.name, 'database');
        expect(result.blockingFailures.first.message, contains('exception'));
      },
    );

    test('ignora mensagens que nao sao preflightRequest', () async {
      final handler = PreflightMessageHandler();

      Message? sent;
      Future<void> capture(String c, Message m) async => sent = m;

      final notRequest = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 0),
        payload: const <String, dynamic>{},
        checksum: 0,
      );

      await handler.handle('c1', notRequest, capture);
      expect(sent, isNull);
    });

    test(
      'info-only checks que falham nao escalam para warning/blocked',
      () async {
        final handler = PreflightMessageHandler(
          checks: {
            'tool_version': () async => const PreflightCheckResult(
                  name: 'tool_version',
                  passed: false,
                  severity: PreflightSeverity.info,
                  message: 'Versao desconhecida',
                ),
          },
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createPreflightRequestMessage(), capture);

        final result = readPreflightFromResponse(sent!);
        // info nunca bloqueia nem alerta
        expect(result.status, PreflightStatus.passed);
        expect(result.warnings, isEmpty);
        expect(result.blockingFailures, isEmpty);
      },
    );

    test('details de check sao preservados no payload', () async {
      final handler = PreflightMessageHandler(
        checks: {
          'disk_space': () async => const PreflightCheckResult(
                name: 'disk_space',
                passed: true,
                severity: PreflightSeverity.warning,
                message: 'OK',
                details: {'freeBytes': 50000000000, 'requiredBytes': 1000000000},
              ),
        },
      );

      Message? sent;
      Future<void> capture(String c, Message m) async => sent = m;

      await handler.handle('c1', createPreflightRequestMessage(), capture);

      final result = readPreflightFromResponse(sent!);
      final check = result.checks.single;
      expect(check.details['freeBytes'], 50000000000);
      expect(check.details['requiredBytes'], 1000000000);
    });
  });
}
