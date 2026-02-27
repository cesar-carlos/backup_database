import 'dart:io';

import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/process/sybase_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockProcessService extends Mock implements ProcessService {}

void main() {
  late _MockProcessService processService;
  late SybaseBackupService service;
  late SybaseConfig config;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(const Duration(seconds: 1));
  });

  setUp(() async {
    processService = _MockProcessService();
    service = SybaseBackupService(processService);
    tempDir = await Directory.systemTemp.createTemp('sybase_backup_test_');
    config = SybaseConfig(
      id: 'cfg-1',
      name: 'Test',
      serverName: 'TestServer',
      databaseName: DatabaseName('testdb'),
      username: 'dba',
      password: 'secret',
      port: PortNumber(2638),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  void stubBackupSuccess({String executable = 'dbisql'}) {
    when(
      () => processService.run(
        executable: executable,
        arguments: any(named: 'arguments'),
        workingDirectory: any(named: 'workingDirectory'),
        environment: any(named: 'environment'),
        timeout: any(named: 'timeout'),
        tag: any(named: 'tag'),
      ),
    ).thenAnswer(
      (_) async => const rd.Success(
        ProcessResult(
          exitCode: 0,
          stdout: 'ok',
          stderr: '',
          duration: Duration(milliseconds: 50),
        ),
      ),
    );
  }

  void stubDbvalidSuccess({Duration delay = Duration.zero}) {
    when(
      () => processService.run(
        executable: 'dbvalid',
        arguments: any(named: 'arguments'),
        workingDirectory: any(named: 'workingDirectory'),
        environment: any(named: 'environment'),
        timeout: any(named: 'timeout'),
        tag: any(named: 'tag'),
      ),
    ).thenAnswer(
      (_) async {
        await Future.delayed(delay);
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: 'ok',
            stderr: '',
            duration: Duration(milliseconds: 100),
          ),
        );
      },
    );
  }

  group('SybaseBackupService - Fase -1 regressao', () {
    test(
      '[B1] verifyDuration reflete tempo real quando verifyAfterBackup=true',
      () async {
        stubBackupSuccess();
        stubDbvalidSuccess(delay: const Duration(milliseconds: 80));

        final fullBackupDir = Directory(
          '${tempDir.path}/${config.databaseNameValue}',
        );
        await fullBackupDir.create(recursive: true);
        await File('${fullBackupDir.path}/mydb.db').writeAsString('x' * 100);

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          verifyAfterBackup: true,
        );

        expect(result.isSuccess(), isTrue);
        result.fold(
          (r) {
            expect(r.metrics, isNotNull);
            expect(
              r.metrics!.verifyDuration.inMilliseconds,
              greaterThanOrEqualTo(80),
              reason:
                  'verifyDuration deve refletir o tempo real de verificacao',
            );
          },
          (_) => fail('Expected success'),
        );
      },
    );

    test(
      '[B2] backupTimeout e verifyTimeout sao passados ao ProcessService',
      () async {
        stubBackupSuccess();
        stubDbvalidSuccess();

        final fullBackupDir = Directory(
          '${tempDir.path}/${config.databaseNameValue}',
        );
        await fullBackupDir.create(recursive: true);
        await File('${fullBackupDir.path}/mydb.db').writeAsString('x' * 100);

        const backupTimeout = Duration(minutes: 5);
        const verifyTimeout = Duration(minutes: 10);

        await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          verifyAfterBackup: true,
          backupTimeout: backupTimeout,
          verifyTimeout: verifyTimeout,
        );

        final backupCalls = verify(
          () => processService.run(
            executable: 'dbisql',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: captureAny(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).captured;

        final verifyCalls = verify(
          () => processService.run(
            executable: 'dbvalid',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: captureAny(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).captured;

        expect(backupCalls, isNotEmpty);
        expect(backupCalls.first, backupTimeout);

        expect(verifyCalls, isNotEmpty);
        expect(verifyCalls.first, verifyTimeout);
      },
    );

    test(
      '[B3] backupType=log e verifyAfterBackup=true registra log_unavailable',
      () async {
        stubBackupSuccess();
        when(
          () => processService.run(
            executable: 'dbbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'ok',
              stderr: '',
              duration: Duration(milliseconds: 50),
            ),
          ),
        );

        final logDir = Directory(
          '${tempDir.path}/testdb_log_2026-01-01T12-00-00',
        );
        await logDir.create(recursive: true);
        await File('${logDir.path}/backup.log').writeAsString('x' * 100);

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          backupType: BackupType.log,
          verifyAfterBackup: true,
          customFileName: 'testdb_log_2026-01-01T12-00-00',
        );

        expect(result.isSuccess(), isTrue);
        result.fold(
          (r) {
            expect(r.metrics, isNotNull);
            expect(
              r.metrics!.flags.verifyPolicy,
              'log_unavailable',
              reason:
                  'Verificacao de log deve ser registrada como indisponivel',
            );
          },
          (_) => fail('Expected success'),
        );
      },
    );

    test(
      '[D1] differential convertido para log usa fluxo dbbackup sem branch differential',
      () async {
        when(
          () => processService.run(
            executable: 'dbisql',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => rd.Failure(
            Exception('dbisql falhou para forcar fallback'),
          ),
        );

        when(
          () => processService.run(
            executable: 'dbbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'ok',
              stderr: '',
              duration: Duration(milliseconds: 50),
            ),
          ),
        );

        final logDir = Directory(
          '${tempDir.path}/testdb_log_2026-01-01T12-00-01',
        );
        await logDir.create(recursive: true);
        await File('${logDir.path}/backup.trn').writeAsString('x' * 100);

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          backupType: BackupType.differential,
          customFileName: 'testdb_log_2026-01-01T12-00-01',
        );

        expect(result.isSuccess(), isTrue);
        result.fold(
          (r) {
            expect(r.metrics, isNotNull);
            expect(r.metrics!.backupType, 'log');
          },
          (_) => fail('Expected success'),
        );
      },
    );
  });

  group('SybaseBackupService - log backup mode (Fase 6)', () {
    test('logBackupMode rename usa -t -r no dbbackup', () async {
      List<String>? dbbackupArgs;
      when(
        () => processService.run(
          executable: any(named: 'executable'),
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final exec = invocation.namedArguments[#executable] as String;
        final args = invocation.namedArguments[#arguments] as List<String>?;
        if (exec == 'dbbackup' && args != null) {
          dbbackupArgs = args;
          final yIndex = args.indexOf('-y');
          if (yIndex >= 0 && yIndex + 1 < args.length) {
            final backupPath = args[yIndex + 1];
            final logDir = Directory(backupPath);
            await logDir.create(recursive: true);
            await File('${logDir.path}/backup.trn').writeAsString('x' * 100);
          }
        }
        if (exec == 'dbisql') {
          return const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'fail',
              duration: Duration(milliseconds: 10),
            ),
          );
        }
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: 'ok',
            stderr: '',
            duration: Duration(milliseconds: 50),
          ),
        );
      });

      final result = await service.executeBackup(
        config: config,
        outputDirectory: tempDir.path,
        backupType: BackupType.log,
        sybaseBackupOptions: const SybaseBackupOptions(
          logBackupMode: SybaseLogBackupMode.rename,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(dbbackupArgs, isNotNull);
      expect(dbbackupArgs!.contains('-t'), isTrue);
      expect(dbbackupArgs!.contains('-r'), isTrue);
      expect(dbbackupArgs!.contains('-x'), isFalse);
    });

    test('logBackupMode truncate usa -t -x no dbbackup', () async {
      List<String>? dbbackupArgs;
      when(
        () => processService.run(
          executable: any(named: 'executable'),
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final exec = invocation.namedArguments[#executable] as String;
        final args = invocation.namedArguments[#arguments] as List<String>?;
        if (exec == 'dbbackup' && args != null) {
          dbbackupArgs = args;
          final yIndex = args.indexOf('-y');
          if (yIndex >= 0 && yIndex + 1 < args.length) {
            final backupPath = args[yIndex + 1];
            final logDir = Directory(backupPath);
            await logDir.create(recursive: true);
            await File('${logDir.path}/backup.trn').writeAsString('x' * 100);
          }
        }
        if (exec == 'dbisql') {
          return const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'fail',
              duration: Duration(milliseconds: 10),
            ),
          );
        }
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: 'ok',
            stderr: '',
            duration: Duration(milliseconds: 50),
          ),
        );
      });

      final result = await service.executeBackup(
        config: config,
        outputDirectory: tempDir.path,
        backupType: BackupType.log,
      );

      expect(result.isSuccess(), isTrue);
      expect(dbbackupArgs, isNotNull);
      expect(dbbackupArgs!.contains('-t'), isTrue);
      expect(dbbackupArgs!.contains('-x'), isTrue);
    });
  });

  group('SybaseBackupService - AUTO TUNE WRITERS (Fase 5)', () {
    test('autoTuneWriters ON inclui clausula no SQL Full', () async {
      String? capturedSql;
      when(
        () => processService.run(
          executable: 'dbisql',
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.namedArguments[#arguments] as List<String>?;
        if (args != null && args.length >= 4) {
          capturedSql = args[3];
        }
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: 'ok',
            stderr: '',
            duration: Duration(milliseconds: 50),
          ),
        );
      });
      stubDbvalidSuccess();

      final fullBackupDir = Directory(
        '${tempDir.path}/${config.databaseNameValue}',
      );
      await fullBackupDir.create(recursive: true);
      await File('${fullBackupDir.path}/testdb.db').writeAsString('x' * 100);

      final result = await service.executeBackup(
        config: config,
        outputDirectory: tempDir.path,
        verifyAfterBackup: true,
        sybaseBackupOptions: const SybaseBackupOptions(autoTuneWriters: true),
      );

      expect(result.isSuccess(), isTrue);
      expect(capturedSql, isNotNull);
      expect(capturedSql, contains('AUTO TUNE WRITERS ON'));
    });

    test('autoTuneWriters OFF inclui clausula no SQL Full', () async {
      String? capturedSql;
      when(
        () => processService.run(
          executable: 'dbisql',
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.namedArguments[#arguments] as List<String>?;
        if (args != null && args.length >= 4) {
          capturedSql = args[3];
        }
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: 'ok',
            stderr: '',
            duration: Duration(milliseconds: 50),
          ),
        );
      });
      stubDbvalidSuccess();

      final fullBackupDir = Directory(
        '${tempDir.path}/${config.databaseNameValue}',
      );
      await fullBackupDir.create(recursive: true);
      await File('${fullBackupDir.path}/testdb.db').writeAsString('x' * 100);

      final result = await service.executeBackup(
        config: config,
        outputDirectory: tempDir.path,
        verifyAfterBackup: true,
      );

      expect(result.isSuccess(), isTrue);
      expect(capturedSql, isNotNull);
      expect(capturedSql, contains('AUTO TUNE WRITERS OFF'));
    });
  });

  group('SybaseBackupService - metricas metodo/estrategia', () {
    test(
      'sybaseOptions inclui backupMethod e connectionStrategy em Full',
      () async {
        stubBackupSuccess();
        stubDbvalidSuccess();

        final fullBackupDir = Directory(
          '${tempDir.path}/${config.databaseNameValue}',
        );
        await fullBackupDir.create(recursive: true);
        await File('${fullBackupDir.path}/mydb.db').writeAsString('x' * 100);

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          verifyAfterBackup: true,
        );

        expect(result.isSuccess(), isTrue);
        result.fold(
          (r) {
            expect(r.metrics?.sybaseOptions, isNotNull);
            expect(
              r.metrics!.sybaseOptions!['backupMethod'],
              anyOf('dbisql', 'dbbackup'),
            );
            expect(
              r.metrics!.sybaseOptions!['connectionStrategy'],
              isNotNull,
            );
          },
          (_) => fail('Expected success'),
        );
      },
    );
  });

  group('SybaseBackupService - estrategia e fallback (Fase 8)', () {
    test(
      'selecao estrategia: dbisql estrategia 2 usada quando estrategia 1 falha',
      () async {
        var dbisqlCallCount = 0;
        when(
          () => processService.run(
            executable: 'dbisql',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((_) async {
          dbisqlCallCount++;
          if (dbisqlCallCount == 1) {
            return const rd.Success(
              ProcessResult(
                exitCode: 1,
                stdout: '',
                stderr: 'fail',
                duration: Duration(milliseconds: 10),
              ),
            );
          }
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'ok',
              stderr: '',
              duration: Duration(milliseconds: 50),
            ),
          );
        });
        stubDbvalidSuccess();

        final fullBackupDir = Directory(
          '${tempDir.path}/${config.databaseNameValue}',
        );
        await fullBackupDir.create(recursive: true);
        await File('${fullBackupDir.path}/testdb.db').writeAsString('x' * 100);

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          verifyAfterBackup: true,
        );

        expect(result.isSuccess(), isTrue);
        expect(dbisqlCallCount, greaterThanOrEqualTo(2));
        result.fold(
          (r) {
            expect(r.metrics?.sybaseOptions?['backupMethod'], 'dbisql');
            expect(r.metrics!.sybaseOptions!['connectionStrategy'], isNotNull);
          },
          (_) => fail('Expected success'),
        );
      },
    );

    test(
      'fallback dbisql -> dbbackup: dbbackup usado quando dbisql falha',
      () async {
        when(
          () => processService.run(
            executable: 'dbisql',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'unable to connect',
              duration: Duration(milliseconds: 10),
            ),
          ),
        );

        when(
          () => processService.run(
            executable: 'dbbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'ok',
              stderr: '',
              duration: Duration(milliseconds: 50),
            ),
          ),
        );
        stubDbvalidSuccess();

        final fullBackupDir = Directory(
          '${tempDir.path}/${config.databaseNameValue}',
        );
        await fullBackupDir.create(recursive: true);
        await File('${fullBackupDir.path}/testdb.db').writeAsString('x' * 100);

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          verifyAfterBackup: true,
        );

        expect(result.isSuccess(), isTrue);
        result.fold(
          (r) {
            expect(r.metrics?.sybaseOptions?['backupMethod'], 'dbbackup');
          },
          (_) => fail('Expected success'),
        );
      },
    );

    test(
      'dbvalid chamado com DBF quando arquivo .db existe no backup',
      () async {
        stubBackupSuccess();
        List<String>? dbvalidArgs;
        when(
          () => processService.run(
            executable: 'dbvalid',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          dbvalidArgs =
              invocation.namedArguments[#arguments] as List<String>?;
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'ok',
              stderr: '',
              duration: Duration(milliseconds: 100),
            ),
          );
        });

        final fullBackupDir = Directory(
          '${tempDir.path}/${config.databaseNameValue}',
        );
        await fullBackupDir.create(recursive: true);
        await File('${fullBackupDir.path}/testdb.db').writeAsString('x' * 100);

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          verifyAfterBackup: true,
        );

        expect(result.isSuccess(), isTrue);
        expect(dbvalidArgs, isNotNull);
        expect(
          dbvalidArgs!.any((a) => a.startsWith('DBF=') || a.contains('.db')),
          isTrue,
        );
      },
    );

    test(
      'modo strict: falha backup quando dbvalid e dbverify falham',
      () async {
        stubBackupSuccess();
        when(
          () => processService.run(
            executable: 'dbvalid',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'dbvalid failed',
              duration: Duration(milliseconds: 50),
            ),
          ),
        );
        when(
          () => processService.run(
            executable: 'dbverify',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'dbverify failed',
              duration: Duration(milliseconds: 50),
            ),
          ),
        );

        final fullBackupDir = Directory(
          '${tempDir.path}/${config.databaseNameValue}',
        );
        await fullBackupDir.create(recursive: true);
        await File('${fullBackupDir.path}/testdb.db').writeAsString('x' * 100);

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          verifyAfterBackup: true,
          verifyPolicy: VerifyPolicy.strict,
        );

        expect(result.isError(), isTrue);
      },
    );

    test(
      'quando dbvalid falha mas dbverify sucede reporta dbverify',
      () async {
        stubBackupSuccess();
        when(
          () => processService.run(
            executable: 'dbvalid',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'dbvalid failed',
              duration: Duration(milliseconds: 50),
            ),
          ),
        );
        when(
          () => processService.run(
            executable: 'dbverify',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'ok',
              stderr: '',
              duration: Duration(milliseconds: 50),
            ),
          ),
        );

        final fullBackupDir = Directory(
          '${tempDir.path}/${config.databaseNameValue}',
        );
        await fullBackupDir.create(recursive: true);
        await File('${fullBackupDir.path}/testdb.db').writeAsString('x' * 100);

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          verifyAfterBackup: true,
        );

        expect(result.isSuccess(), isTrue);

        final metrics = result.getOrNull()!.metrics!;
        expect(metrics.flags.verifyPolicy, 'dbverify');
        expect(
          metrics.sybaseOptions?['verificationMethod'],
          'dbverify',
        );
      },
    );

    test(
      'quando dbvalid e dbverify falham reporta dbvalid_falhou',
      () async {
        stubBackupSuccess();
        when(
          () => processService.run(
            executable: 'dbvalid',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'dbvalid failed',
              duration: Duration(milliseconds: 50),
            ),
          ),
        );
        when(
          () => processService.run(
            executable: 'dbverify',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'dbverify failed',
              duration: Duration(milliseconds: 50),
            ),
          ),
        );

        final fullBackupDir = Directory(
          '${tempDir.path}/${config.databaseNameValue}',
        );
        await fullBackupDir.create(recursive: true);
        await File('${fullBackupDir.path}/testdb.db').writeAsString('x' * 100);

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          verifyAfterBackup: true,
        );

        expect(result.isSuccess(), isTrue);

        final metrics = result.getOrNull()!.metrics!;
        expect(metrics.flags.verifyPolicy, 'dbvalid_falhou');
        expect(
          metrics.sybaseOptions?['verificationMethod'],
          'dbvalid_falhou',
        );
      },
    );

    test(
      'resolucao arquivo log: usa .trn ou .log no diretorio do backup',
      () async {
        when(
          () => processService.run(
            executable: 'dbisql',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'fail',
              duration: Duration(milliseconds: 10),
            ),
          ),
        );
        when(
          () => processService.run(
            executable: 'dbbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments] as List<String>?;
          if (args != null) {
            final yIndex = args.indexOf('-y');
            if (yIndex >= 0 && yIndex + 1 < args.length) {
              final backupPath = args[yIndex + 1];
              final logDir = Directory(backupPath);
              await logDir.create(recursive: true);
              await File('${logDir.path}/mylog.trn').writeAsString('x' * 200);
            }
          }
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'ok',
              stderr: '',
              duration: Duration(milliseconds: 50),
            ),
          );
        });

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          backupType: BackupType.log,
        );

        expect(result.isSuccess(), isTrue);
        result.fold(
          (r) {
            expect(r.backupPath, contains('mylog.trn'));
            expect(r.fileSize, 200);
          },
          (_) => fail('Expected success'),
        );
      },
    );
  });
}
