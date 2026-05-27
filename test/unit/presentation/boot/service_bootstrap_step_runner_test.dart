import 'dart:io';

import 'package:backup_database/presentation/boot/service_bootstrap_log.dart';
import 'package:backup_database/presentation/boot/service_bootstrap_step_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late File logFile;
  late ServiceBootstrapLog log;
  late ServiceBootstrapStepRunner runner;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('bootstrap_step_runner_');
    logFile = File(p.join(tempDir.path, 'bootstrap.log'));
    log = ServiceBootstrapLog(logPath: logFile.path);
    runner = ServiceBootstrapStepRunner(totalSteps: 3, log: log);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ServiceBootstrapStepRunner.run', () {
    test('writes begin and success entries when action succeeds', () async {
      await runner.run(
        step: 2,
        label: 'doing something',
        action: () async {},
      );
      // S3 da auditoria: o sink agora é async com fila serializada.
      // Forçamos drain para validar conteúdo no arquivo.
      await log.flush();

      final content = await logFile.readAsString();
      expect(content, contains('step 2/3: doing something begin'));
      expect(content, contains('step 2/3: doing something success'));
    });

    test('writes success entry with details when provided', () async {
      await runner.run(
        step: 1,
        label: 'load env',
        action: () async {},
        successDetails: () => 'loaded=42',
      );
      await log.flush();

      final content = await logFile.readAsString();
      expect(
        content,
        contains('step 1/3: load env success (loaded=42)'),
      );
    });

    test('writes failed entry and rethrows on action error', () async {
      await expectLater(
        () => runner.run(
          step: 3,
          label: 'risky',
          action: () async => throw StateError('boom'),
        ),
        throwsStateError,
      );
      await log.flush();

      final content = await logFile.readAsString();
      expect(content, contains('step 3/3: risky failed'));
      expect(content, contains('error: Bad state: boom'));
    });
  });

  group('ServiceBootstrapStepRunner.markAborted', () {
    test('writes an aborted entry with reason and exit code', () async {
      await runner.markAborted(
        step: 4,
        reason: 'global_instance_lock_denied',
        exitCode: 77,
      );
      await log.flush();

      final content = await logFile.readAsString();
      expect(
        content,
        contains(
          'step 4/3: aborted reason=global_instance_lock_denied exit=77',
        ),
      );
    });
  });
}
