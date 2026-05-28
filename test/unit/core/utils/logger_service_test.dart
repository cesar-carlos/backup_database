import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LoggerService.health', () {
    setUp(LoggerService.resetForTesting);
    tearDown(LoggerService.resetForTesting);

    test('reports unhealthy when init not called with logsDirectory', () async {
      await LoggerService.init();

      final health = LoggerService.health;
      expect(health.isHealthy, isFalse);
      expect(health.fileLoggingEnabled, isFalse);
      expect(health.lastBootSentinelWrittenAt, isNull);
    });

    test(
      'writes sentinel line and reports healthy when logsDirectory writable',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'logger_service_health_test',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        await LoggerService.init(logsDirectory: tempDir.path);

        final health = LoggerService.health;
        expect(health.isHealthy, isTrue);
        expect(health.fileLoggingEnabled, isTrue);
        expect(health.lastBootSentinelWrittenAt, isNotNull);
        expect(health.logsDirectory, tempDir.path);
        expect(health.initError, isNull);
        expect(health.lastBootSentinelError, isNull);

        // §audit-2026-05-28: a linha sentinel TEM que aparecer no log
        // do dia. Auditores podem grep `[boot] LoggerService sentinel`
        // para confirmar que o file logging funciona — vs. arquivos
        // vazios silenciosamente (sintoma original).
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final today = DateTime.now().toIso8601String().split('T').first;
        final logFile = File(p.join(tempDir.path, 'app_$today.log'));
        expect(await logFile.exists(), isTrue);
        final content = await logFile.readAsString();
        expect(content, contains('[boot] LoggerService sentinel'));
        expect(content, contains('pid='));
      },
    );

    test(
      'reports unhealthy when logsDirectory points to invalid path',
      () async {
        // Path com chars invalidos no Windows -> init falha
        // controladamente sem propagar exception.
        final invalidPath = Platform.isWindows
            ? r'Z:\definitely\not\exist\<invalid>'
            : '/proc/cannot/write/here';

        await LoggerService.init(logsDirectory: invalidPath);

        final health = LoggerService.health;
        expect(health.isHealthy, isFalse);
        expect(health.fileLoggingEnabled, isFalse);
        // initError pode estar populado OR fileLogger nao foi criado.
        // O importante e que o app NAO crashou e o health reportou degraded.
      },
    );
  });
}
