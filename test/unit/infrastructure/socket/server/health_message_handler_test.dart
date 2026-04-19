import 'package:backup_database/infrastructure/protocol/health_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/health_message_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HealthMessageHandler', () {
    test(
      'sem checks injetados: responde ok com socket=true e uptime calculado',
      () async {
        final start = DateTime.utc(2026, 4, 19, 12);
        final now = DateTime.utc(2026, 4, 19, 13);
        final handler = HealthMessageHandler(
          clock: () => now,
          startTime: start,
        );

        Message? sent;
        Future<void> capture(String clientId, Message msg) async {
          sent = msg;
        }

        await handler.handle(
          'client-1',
          createHealthRequestMessage(requestId: 1),
          capture,
        );

        expect(sent, isNotNull);
        expect(sent!.header.type, MessageType.healthResponse);
        final health = readHealthFromResponse(sent!);
        expect(health.status, ServerHealthStatus.ok);
        expect(health.checks['socket'], isTrue);
        expect(health.uptimeSeconds, 3600);
      },
    );

    test(
      'todos os required checks ok + optional ok: status ok',
      () async {
        final handler = HealthMessageHandler(
          requiredChecks: {'database': () async => true},
          optionalChecks: {'staging': () async => true},
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle(
          'c1',
          createHealthRequestMessage(),
          capture,
        );

        final health = readHealthFromResponse(sent!);
        expect(health.status, ServerHealthStatus.ok);
        expect(health.checks['database'], isTrue);
        expect(health.checks['staging'], isTrue);
        expect(health.message, isNull);
      },
    );

    test(
      'optional check falha: status degraded com message diagnostica',
      () async {
        final handler = HealthMessageHandler(
          requiredChecks: {'database': () async => true},
          optionalChecks: {'staging': () async => false},
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createHealthRequestMessage(), capture);

        final health = readHealthFromResponse(sent!);
        expect(health.status, ServerHealthStatus.degraded);
        expect(health.checks['staging'], isFalse);
        expect(health.message, contains('staging'));
      },
    );

    test(
      'required check falha: status unhealthy',
      () async {
        final handler = HealthMessageHandler(
          requiredChecks: {'database': () async => false},
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createHealthRequestMessage(), capture);

        final health = readHealthFromResponse(sent!);
        expect(health.status, ServerHealthStatus.unhealthy);
        expect(health.checks['database'], isFalse);
        expect(health.message, contains('database'));
      },
    );

    test(
      'check que lanca excecao e tratado como false (fail-closed)',
      () async {
        final handler = HealthMessageHandler(
          requiredChecks: {
            'database': () async => throw Exception('connection refused'),
          },
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createHealthRequestMessage(), capture);

        final health = readHealthFromResponse(sent!);
        expect(health.status, ServerHealthStatus.unhealthy);
        expect(health.checks['database'], isFalse);
      },
    );

    test('ignora mensagens que nao sao healthRequest', () async {
      final handler = HealthMessageHandler();

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
      'multiple checks: agregacao prioriza required > optional > ok',
      () async {
        final handler = HealthMessageHandler(
          requiredChecks: {
            'db': () async => true,
            'license': () async => true,
          },
          optionalChecks: {
            'cache': () async => false,
            'metrics': () async => true,
          },
        );

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createHealthRequestMessage(), capture);

        final health = readHealthFromResponse(sent!);
        // 1 optional falhou, nenhum required falhou -> degraded
        expect(health.status, ServerHealthStatus.degraded);
        expect(health.checks['db'], isTrue);
        expect(health.checks['license'], isTrue);
        expect(health.checks['cache'], isFalse);
        expect(health.checks['metrics'], isTrue);
      },
    );

    test(
      'serverTimeUtc usa o clock injetado',
      () async {
        final fixed = DateTime.utc(2026, 4, 19, 23, 59);
        final handler = HealthMessageHandler(clock: () => fixed);

        Message? sent;
        Future<void> capture(String c, Message m) async => sent = m;

        await handler.handle('c1', createHealthRequestMessage(), capture);
        final health = readHealthFromResponse(sent!);
        expect(health.serverTimeUtc, fixed);
      },
    );
  });
}
