import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/external/process/firebird_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class _MockProcessService extends Mock implements ProcessService {}

void main() {
  late _MockProcessService processService;
  late FirebirdBackupService service;
  late Directory tempDir;
  late FirebirdConfig tcpConfig;

  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(<String, String>{});
    registerFallbackValue(const Duration(seconds: 1));
    registerFallbackValue(VerifyPolicy.strict);
  });

  setUp(() async {
    FirebirdBackupService.resetGbakZProbeCacheForTest();
    processService = _MockProcessService();
    service = FirebirdBackupService(
      processService,
      enableGbakZRuntimeProbe: false,
    );
    tempDir = await Directory.systemTemp.createTemp('firebird_backup_service_');
    tcpConfig = FirebirdConfig(
      name: 'fb-local',
      host: 'srv.example',
      databaseFile: '/data/app.fdb',
      username: 'sysdba',
      password: 'masterkey',
      port: PortNumber(3050),
    );
    when(
      () => processService.run(
        executable: 'isql',
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
          stderr: 'isql default stub skips MON path',
          duration: Duration(milliseconds: 1),
        ),
      ),
    );
  });

  tearDown(() async {
    FirebirdBackupService.resetGbakZProbeCacheForTest();
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    }
  });

  group('FirebirdBackupService', () {
    test('executeBackup with log uses nbackup -B 1 not gbak', () async {
      when(
        () => processService.run(
          executable: 'nbackup',
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.namedArguments[#arguments]! as List<String>;
        expect(args, contains('1'));
        final outPath = args.last;
        await File(outPath).writeAsBytes(List<int>.filled(10, 1));
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: '',
            stderr: '',
            duration: Duration(milliseconds: 2),
          ),
        );
      });

      await File(p.join(tempDir.path, 'app_full_seed.nbk')).writeAsString('x');

      final result = await service.executeBackup(
        config: tcpConfig,
        context: BackupExecutionContext(
          outputDirectory: tempDir.path,
          scheduleId: 'sched-1',
          backupType: BackupType.log,
        ),
      );

      expect(result.isSuccess(), isTrue);
      verifyNever(
        () => processService.run(
          executable: 'gbak',
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      );
      verify(
        () => processService.run(
          executable: 'nbackup',
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).called(1);
    });

    test(
      'executeBackup retries nbackup with -PROVIDER Engine12 on legacy auth',
      () async {
        var nCalls = 0;
        when(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          nCalls++;
          final args = invocation.namedArguments[#arguments]! as List<String>;
          final outPath = args.last;
          if (nCalls == 1) {
            expect(args, isNot(contains('-PROVIDER')));
            return const rd.Success(
              ProcessResult(
                exitCode: 1,
                stdout: '',
                stderr:
                    'Your user name and password are not defined. Ask your '
                    'database admin.',
                duration: Duration(milliseconds: 1),
              ),
            );
          }
          expect(args.indexOf('-PROVIDER'), lessThan(args.indexOf('-USER')));
          expect(args, contains('Engine12'));
          await File(outPath).writeAsBytes(List<int>.filled(12, 2));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 2),
            ),
          );
        });

        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-nb-retry',
          ),
        );

        expect(result.isSuccess(), isTrue);
        expect(nCalls, 2);
        verify(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(2);
      },
    );

    test(
      'executeBackup does not retry nbackup legacy provider when hint is v25',
      () async {
        var nCalls = 0;
        final cfg = FirebirdConfig(
          name: 'fb-v25',
          host: 'srv.example',
          databaseFile: '/data/app.fdb',
          username: 'sysdba',
          password: 'masterkey',
          port: PortNumber(3050),
          serverVersionHint: FirebirdServerVersionHint.v25,
        );
        when(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((_) async {
          nCalls++;
          return const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr:
                  'Your user name and password are not defined. Ask your '
                  'database admin.',
              duration: Duration(milliseconds: 1),
            ),
          );
        });

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-nb-v25',
          ),
        );

        expect(result.isError(), isTrue);
        expect(nCalls, 1);
      },
    );

    test(
      'executeBackup fullSingle passes -SE service_mgr when hint v30 and '
      'serviceManager auto',
      () async {
        final cfg = FirebirdConfig(
          name: 'fb-v30',
          host: 'srv.example',
          databaseFile: '/data/app.fdb',
          username: 'sysdba',
          password: 'masterkey',
          port: PortNumber(3050),
          serverVersionHint: FirebirdServerVersionHint.v30,
        );
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          expect(args.indexOf('-b'), lessThan(args.indexOf('-SE')));
          expect(args, contains('-SE'));
          expect(args, contains('srv.example/3050:service_mgr'));
          final outPath = args.last;
          await File(outPath).writeAsBytes(List<int>.filled(10, 1));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 2),
            ),
          );
        });

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-gbak-se',
            backupType: BackupType.fullSingle,
          ),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(1);
      },
    );

    test(
      'executeBackup fullSingle omits -SE when serviceManagerMode never',
      () async {
        final cfg = FirebirdConfig(
          name: 'fb-no-se',
          host: 'srv.example',
          databaseFile: '/data/app.fdb',
          username: 'sysdba',
          password: 'masterkey',
          port: PortNumber(3050),
          serverVersionHint: FirebirdServerVersionHint.v40,
          serviceManagerMode: FirebirdServiceManagerMode.never,
        );
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          expect(args, isNot(contains('-SE')));
          final outPath = args.last;
          await File(outPath).writeAsBytes(List<int>.filled(10, 1));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 2),
            ),
          );
        });

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-gbak-nose',
            backupType: BackupType.fullSingle,
          ),
        );

        expect(result.isSuccess(), isTrue);
      },
    );

    test(
      'executeBackup full (nbackup) passes -SE service_mgr when hint v30 and '
      'serviceManager auto',
      () async {
        final cfg = FirebirdConfig(
          name: 'fb-nb-se',
          host: 'srv.example',
          databaseFile: '/data/app.fdb',
          username: 'sysdba',
          password: 'masterkey',
          port: PortNumber(3050),
          serverVersionHint: FirebirdServerVersionHint.v30,
        );
        when(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          expect(args.indexOf('-PASSWORD'), lessThan(args.indexOf('-SE')));
          expect(args.indexOf('-SE'), lessThan(args.indexOf('-B')));
          expect(args, contains('-SE'));
          expect(args, contains('srv.example/3050:service_mgr'));
          final outPath = args.last;
          await File(outPath).writeAsBytes(List<int>.filled(64, 1));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 5),
            ),
          );
        });

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-nb-se',
          ),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(1);
      },
    );

    test(
      'executeBackup full (nbackup) omits -SE when serviceManagerMode never',
      () async {
        final cfg = FirebirdConfig(
          name: 'fb-nb-nose',
          host: 'srv.example',
          databaseFile: '/data/app.fdb',
          username: 'sysdba',
          password: 'masterkey',
          port: PortNumber(3050),
          serverVersionHint: FirebirdServerVersionHint.v40,
          serviceManagerMode: FirebirdServiceManagerMode.never,
        );
        when(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          expect(args, isNot(contains('-SE')));
          final outPath = args.last;
          await File(outPath).writeAsBytes(List<int>.filled(64, 1));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 5),
            ),
          );
        });

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-nb-nose',
          ),
        );

        expect(result.isSuccess(), isTrue);
      },
    );

    test(
      'executeBackup rejects strict verify with physical full before nbackup',
      () async {
        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-strict-nb',
            verifyAfterBackup: true,
            verifyPolicy: VerifyPolicy.strict,
          ),
        );

        expect(result.isError(), isTrue);
        verifyNever(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        );
      },
    );

    test(
      'executeBackup fullSingle with verify runs gbak -c after gbak -b',
      () async {
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          if (args.contains('-b')) {
            await File(args.last).writeAsBytes(List<int>.filled(14, 4));
            return const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: '',
                stderr: '',
                duration: Duration(milliseconds: 2),
              ),
            );
          }
          if (args.contains('-c')) {
            expect(args, contains('-y'));
            return const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: '',
                stderr: '',
                duration: Duration(milliseconds: 2),
              ),
            );
          }
          fail('unexpected gbak arguments: $args');
        });

        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-verify-ok',
            backupType: BackupType.fullSingle,
            verifyAfterBackup: true,
          ),
        );

        expect(result.isSuccess(), isTrue);
        final metrics = result.getOrNull()!.metrics!;
        expect(metrics.verifyDuration, isNot(equals(Duration.zero)));
        expect(metrics.flags.verifyPolicy, VerifyPolicy.bestEffort.name);
        verify(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(2);
      },
    );

    test(
      'executeBackup fullSingle verify strict fails when gbak -c fails',
      () async {
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          if (args.contains('-b')) {
            await File(args.last).writeAsBytes(List<int>.filled(14, 5));
            return const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: '',
                stderr: '',
                duration: Duration(milliseconds: 2),
              ),
            );
          }
          return const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'gbak restore verify failed',
              duration: Duration(milliseconds: 1),
            ),
          );
        });

        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-verify-fail',
            backupType: BackupType.fullSingle,
            verifyAfterBackup: true,
            verifyPolicy: VerifyPolicy.strict,
          ),
        );

        expect(result.isError(), isTrue);
        verify(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(2);
      },
    );

    test(
      'executeBackup fullSingle verify bestEffort continues when gbak -c fails',
      () async {
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          if (args.contains('-b')) {
            await File(args.last).writeAsBytes(List<int>.filled(14, 6));
            return const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: '',
                stderr: '',
                duration: Duration(milliseconds: 2),
              ),
            );
          }
          return const rd.Success(
            ProcessResult(
              exitCode: 2,
              stdout: '',
              stderr: 'non-fatal verify',
              duration: Duration(milliseconds: 1),
            ),
          );
        });

        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-verify-soft',
            backupType: BackupType.fullSingle,
            verifyAfterBackup: true,
          ),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(2);
      },
    );

    test(
      'executeBackup fullSingle verify gbak -c passes -SE when hint v30',
      () async {
        final cfg = FirebirdConfig(
          name: 'fb-verify-se',
          host: 'srv.example',
          databaseFile: '/data/app.fdb',
          username: 'sysdba',
          password: 'masterkey',
          port: PortNumber(3050),
          serverVersionHint: FirebirdServerVersionHint.v30,
        );
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          if (args.contains('-b')) {
            await File(args.last).writeAsBytes(List<int>.filled(14, 4));
            return const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: '',
                stderr: '',
                duration: Duration(milliseconds: 2),
              ),
            );
          }
          if (args.contains('-c')) {
            expect(args.indexOf('-c'), lessThan(args.indexOf('-SE')));
            expect(args, contains('srv.example/3050:service_mgr'));
            return const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: '',
                stderr: '',
                duration: Duration(milliseconds: 2),
              ),
            );
          }
          fail('unexpected gbak arguments: $args');
        });

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-verify-se',
            backupType: BackupType.fullSingle,
            verifyAfterBackup: true,
          ),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(2);
      },
    );

    test('executeBackup fails when embedded database path empty', () async {
      final embedded = FirebirdConfig(
        name: 'emb',
        host: 'localhost',
        databaseFile: '   ',
        username: 'u',
        password: 'p',
        useEmbedded: true,
      );

      final result = await service.executeBackup(
        config: embedded,
        context: BackupExecutionContext(
          outputDirectory: tempDir.path,
          scheduleId: 'sched-1',
        ),
      );

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<ValidationFailure>()),
      );
      verifyNever(
        () => processService.run(
          executable: any(named: 'executable'),
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      );
    });

    test(
      'executeBackup embedded v25 skips client library plugin guard',
      () async {
        final dbPath = p.join(tempDir.path, 'e25.fdb');
        await File(dbPath).writeAsBytes(<int>[1, 2, 3]);
        final cfg = FirebirdConfig(
          name: 'e25',
          host: 'localhost',
          databaseFile: dbPath,
          username: 'u',
          password: 'p',
          useEmbedded: true,
          serverVersionHint: FirebirdServerVersionHint.v25,
        );
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          await File(args.last).writeAsBytes(List<int>.filled(8, 1));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 3),
            ),
          );
        });

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-e25',
            backupType: BackupType.fullSingle,
          ),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(1);
      },
    );

    test(
      'executeBackup rejects embedded FB3 hint on Windows without client library path',
      skip: !Platform.isWindows,
      () async {
        final dbPath = p.join(tempDir.path, 'edb_no_client.fdb');
        await File(dbPath).writeAsBytes(<int>[1, 2]);
        final cfg = FirebirdConfig(
          name: 'emb3',
          host: 'localhost',
          databaseFile: dbPath,
          username: 'sysdba',
          password: 'x',
          useEmbedded: true,
          serverVersionHint: FirebirdServerVersionHint.v30,
        );

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-emb3',
            backupType: BackupType.fullSingle,
          ),
        );

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (Object f) {
            expect(f, isA<ValidationFailure>());
            expect(
              (f as ValidationFailure).message,
              contains('Client library path'),
            );
          },
        );
        verifyNever(
          () => processService.run(
            executable: any(named: 'executable'),
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        );
      },
    );

    test(
      'executeBackup rejects embedded on Windows when engine12.dll is missing',
      skip: !Platform.isWindows,
      () async {
        final root = Directory(p.join(tempDir.path, 'fb_install_no_engine'));
        final binDir = Directory(p.join(root.path, 'bin'));
        final pluginsDir = Directory(p.join(root.path, 'plugins'));
        binDir.createSync(recursive: true);
        pluginsDir.createSync(recursive: true);
        final clientPath = p.join(binDir.path, 'fbclient.dll');
        await File(clientPath).writeAsString('x');
        final dbPath = p.join(tempDir.path, 'edb_no_engine.fdb');
        await File(dbPath).writeAsBytes(<int>[1]);

        final cfg = FirebirdConfig(
          name: 'embne',
          host: 'localhost',
          databaseFile: dbPath,
          username: 'u',
          password: 'p',
          useEmbedded: true,
          clientLibraryPath: clientPath,
          serverVersionHint: FirebirdServerVersionHint.v30,
        );

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-ne',
            backupType: BackupType.fullSingle,
          ),
        );

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (Object f) {
            expect(f, isA<ValidationFailure>());
            expect((f as ValidationFailure).message, contains('engine12.dll'));
          },
        );
        verifyNever(
          () => processService.run(
            executable: any(named: 'executable'),
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        );
      },
    );

    test(
      'executeBackup proceeds when embedded Windows install has engine12',
      skip: !Platform.isWindows,
      () async {
        final root = Directory(p.join(tempDir.path, 'fb_install_ok'));
        final binDir = Directory(p.join(root.path, 'bin'));
        final pluginsDir = Directory(p.join(root.path, 'plugins'));
        binDir.createSync(recursive: true);
        pluginsDir.createSync(recursive: true);
        final clientPath = p.join(binDir.path, 'fbclient.dll');
        await File(clientPath).writeAsString('x');
        await File(p.join(pluginsDir.path, 'engine12.dll')).writeAsString('p');
        final dbPath = p.join(tempDir.path, 'edb_ok.fdb');
        await File(dbPath).writeAsBytes(<int>[1]);

        final cfg = FirebirdConfig(
          name: 'embok',
          host: 'localhost',
          databaseFile: dbPath,
          username: 'u',
          password: 'p',
          useEmbedded: true,
          clientLibraryPath: clientPath,
          serverVersionHint: FirebirdServerVersionHint.v30,
        );

        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          await File(args.last).writeAsBytes(List<int>.filled(16, 2));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 4),
            ),
          );
        });

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-ok',
            backupType: BackupType.fullSingle,
          ),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(1);
      },
    );

    test(
      'executeBackup rejects embedded on Windows when engine13.dll is missing',
      skip: !Platform.isWindows,
      () async {
        final root = Directory(p.join(tempDir.path, 'fb_install_no_engine13'));
        final binDir = Directory(p.join(root.path, 'bin'));
        final pluginsDir = Directory(p.join(root.path, 'plugins'));
        binDir.createSync(recursive: true);
        pluginsDir.createSync(recursive: true);
        final clientPath = p.join(binDir.path, 'fbclient.dll');
        await File(clientPath).writeAsString('x');
        final dbPath = p.join(tempDir.path, 'edb_no_engine13.fdb');
        await File(dbPath).writeAsBytes(<int>[1]);

        final cfg = FirebirdConfig(
          name: 'emb4',
          host: 'localhost',
          databaseFile: dbPath,
          username: 'u',
          password: 'p',
          useEmbedded: true,
          clientLibraryPath: clientPath,
          serverVersionHint: FirebirdServerVersionHint.v40,
        );

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-ne13',
            backupType: BackupType.fullSingle,
          ),
        );

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (Object f) {
            expect(f, isA<ValidationFailure>());
            expect((f as ValidationFailure).message, contains('engine13.dll'));
          },
        );
        verifyNever(
          () => processService.run(
            executable: any(named: 'executable'),
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        );
      },
    );

    test(
      'executeBackup proceeds when embedded Windows install has engine13',
      skip: !Platform.isWindows,
      () async {
        final root = Directory(p.join(tempDir.path, 'fb_install_ok_fb4'));
        final binDir = Directory(p.join(root.path, 'bin'));
        final pluginsDir = Directory(p.join(root.path, 'plugins'));
        binDir.createSync(recursive: true);
        pluginsDir.createSync(recursive: true);
        final clientPath = p.join(binDir.path, 'fbclient.dll');
        await File(clientPath).writeAsString('x');
        await File(p.join(pluginsDir.path, 'engine13.dll')).writeAsString('p');
        final dbPath = p.join(tempDir.path, 'edb_ok_fb4.fdb');
        await File(dbPath).writeAsBytes(<int>[1]);

        final cfg = FirebirdConfig(
          name: 'embok4',
          host: 'localhost',
          databaseFile: dbPath,
          username: 'u',
          password: 'p',
          useEmbedded: true,
          clientLibraryPath: clientPath,
          serverVersionHint: FirebirdServerVersionHint.v40,
        );

        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          await File(args.last).writeAsBytes(List<int>.filled(16, 3));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 4),
            ),
          );
        });

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-ok4',
            backupType: BackupType.fullSingle,
          ),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(1);
      },
    );

    test(
      'executeBackup fullSingle hint v40 passes crypt key as -KEYNAME to gbak',
      () async {
        final cfg = tcpConfig.copyWith(
          serverVersionHint: FirebirdServerVersionHint.v40,
          cryptKey: 'MyDbKey',
        );
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          expect(args, contains('-KEYNAME'));
          expect(args, contains('MyDbKey'));
          expect(args, isNot(contains('-key')));
          await File(args.last).writeAsBytes(List<int>.filled(32, 1));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 3),
            ),
          );
        });

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-keyname',
            backupType: BackupType.fullSingle,
          ),
        );

        expect(result.isSuccess(), isTrue);
      },
    );

    test(
      'executeBackup passes tcp connection spec and crypt key to gbak',
      () async {
        final cfg = FirebirdConfig(
          name: 'k',
          host: 'h',
          databaseFile: '/db/x.fdb',
          username: 'u',
          password: 'p',
          cryptKey: '  sekrit  ',
        );
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          expect(args, contains('-b'));
          expect(args, contains('-user'));
          expect(args, contains('u'));
          expect(args, contains('-pas'));
          expect(args, contains('p'));
          expect(args, contains('-key'));
          expect(args, contains('sekrit'));
          expect(args, contains('h/3050:/db/x.fdb'));
          final outPath = args.last;
          await File(outPath).writeAsBytes(List<int>.filled(64, 1));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 5),
            ),
          );
        });

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-1',
            backupType: BackupType.fullSingle,
          ),
        );

        expect(result.isSuccess(), isTrue);
        result.fold(
          (r) {
            final metrics = r.metrics!;
            expect(metrics.flags.tool, 'gbak');
            expect(metrics.flags.firebirdVersion, 'auto');
          },
          (_) => fail('expected success'),
        );
        verify(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(1);
      },
    );

    test('executeBackup metrics flags carry serverVersionHint wire', () async {
      final cfg = FirebirdConfig(
        name: 'v',
        host: 'h',
        databaseFile: '/db/x.fdb',
        username: 'u',
        password: 'p',
        serverVersionHint: FirebirdServerVersionHint.v40,
      );
      when(
        () => processService.run(
          executable: 'gbak',
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.namedArguments[#arguments]! as List<String>;
        await File(args.last).writeAsBytes(List<int>.filled(16, 3));
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: '',
            stderr: '',
            duration: Duration(milliseconds: 4),
          ),
        );
      });

      final result = await service.executeBackup(
        config: cfg,
        context: BackupExecutionContext(
          outputDirectory: tempDir.path,
          scheduleId: 'sched-1',
          backupType: BackupType.fullSingle,
        ),
      );

      expect(result.isSuccess(), isTrue);
      result.fold(
        (r) {
          final metrics = r.metrics!;
          expect(metrics.flags.tool, 'gbak');
          expect(metrics.flags.firebirdVersion, 'v40');
        },
        (_) => fail('expected success'),
      );
    });

    test(
      'executeBackup prepends client library dir to Path in environment',
      () async {
        final lib = Platform.isWindows
            ? r'C:\Firebird_4_0\bin\fbclient.dll'
            : '/opt/firebird/lib/libfbclient.so';
        final cfg = FirebirdConfig(
          name: 'cl',
          host: 'h',
          databaseFile: '/db/x.fdb',
          username: 'u',
          password: 'p',
          clientLibraryPath: lib,
        );
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final env =
              invocation.namedArguments[#environment] as Map<String, String>?;
          expect(env, isNotNull);
          final key = Platform.isWindows ? 'Path' : 'PATH';
          expect(env!.containsKey(key), isTrue);
          final pathValue = env[key];
          expect(pathValue, isNotNull);
          expect(
            pathValue,
            startsWith(
              Platform.isWindows ? r'C:\Firebird_4_0\bin' : '/opt/firebird/lib',
            ),
          );
          final args = invocation.namedArguments[#arguments]! as List<String>;
          final outPath = args.last;
          await File(outPath).writeAsBytes(List<int>.filled(32, 2));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 5),
            ),
          );
        });

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-1',
            backupType: BackupType.fullSingle,
          ),
        );

        expect(result.isSuccess(), isTrue);
      },
    );

    test(
      'executeBackup returns BackupFailure when gbak exits non-zero',
      () async {
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          final outPath = args.last;
          await File(outPath).writeAsString('partial');
          return const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'authentication failed',
              duration: Duration(milliseconds: 2),
            ),
          );
        });

        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-1',
            backupType: BackupType.fullSingle,
          ),
        );

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (f) {
            expect(f, isA<BackupFailure>());
            expect(
              (f as BackupFailure).message.toLowerCase(),
              contains('autenticacao'),
            );
          },
        );
      },
    );

    test('executeBackup fails when backup file size is zero', () async {
      when(
        () => processService.run(
          executable: 'gbak',
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.namedArguments[#arguments]! as List<String>;
        await File(args.last).writeAsString('');
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: '',
            stderr: '',
            duration: Duration(milliseconds: 2),
          ),
        );
      });

      final result = await service.executeBackup(
        config: tcpConfig,
        context: BackupExecutionContext(
          outputDirectory: tempDir.path,
          scheduleId: 'sched-1',
          backupType: BackupType.fullSingle,
        ),
      );

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<BackupFailure>()),
      );
    });

    test(
      'executeBackup rejects physical full when crypt key is set',
      () async {
        final cfg = FirebirdConfig(
          name: 'k',
          host: 'h',
          databaseFile: '/db/x.fdb',
          username: 'u',
          password: 'p',
          cryptKey: 'secret',
        );

        final result = await service.executeBackup(
          config: cfg,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-1',
          ),
        );

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (f) {
            expect(f, isA<ValidationFailure>());
            expect(
              (f as ValidationFailure).message.toLowerCase(),
              contains('criptografia'),
            );
          },
        );
        verifyNever(
          () => processService.run(
            executable: any(named: 'executable'),
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        );
      },
    );

    test(
      'executeBackup full runs nbackup level 0 and tags metrics tool',
      () async {
        when(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          expect(args, contains('-B'));
          expect(args, contains('0'));
          expect(args, contains('-USER'));
          expect(args, contains('sysdba'));
          expect(args, contains('-PASSWORD'));
          expect(args, contains('masterkey'));
          expect(args, contains('srv.example/3050:/data/app.fdb'));
          final outPath = args.last;
          expect(outPath, endsWith('.nbk'));
          await File(outPath).writeAsBytes(List<int>.filled(64, 1));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 5),
            ),
          );
        });

        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-1',
          ),
        );

        expect(result.isSuccess(), isTrue);
        result.fold(
          (r) {
            expect(r.backupPath, endsWith('.nbk'));
            final metrics = r.metrics!;
            expect(metrics.flags.tool, 'nbackup');
          },
          (_) => fail('expected success'),
        );
        verify(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(1);
      },
    );

    test('executeBackup differential runs nbackup -B 1', () async {
      when(
        () => processService.run(
          executable: 'nbackup',
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.namedArguments[#arguments]! as List<String>;
        expect(args, contains('-B'));
        expect(args, contains('1'));
        final outPath = args.last;
        expect(outPath, contains('_nbackup_B1_'));
        expect(outPath, endsWith('.nbk'));
        await File(outPath).writeAsBytes(List<int>.filled(32, 2));
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: '',
            stderr: '',
            duration: Duration(milliseconds: 3),
          ),
        );
      });

      await File(p.join(tempDir.path, 'app_full_seed.nbk')).writeAsString('x');

      final result = await service.executeBackup(
        config: tcpConfig,
        context: BackupExecutionContext(
          outputDirectory: tempDir.path,
          scheduleId: 'sched-diff',
          backupType: BackupType.differential,
        ),
      );

      expect(result.isSuccess(), isTrue);
      result.fold(
        (r) {
          expect(r.metrics!.flags.tool, 'nbackup');
          expect(r.executedBackupType, isNull);
        },
        (_) => fail('expected success'),
      );
    });

    test(
      r'executeBackup FB4 differential uses parent GUID from RDB$BACKUP_HISTORY',
      () async {
        const parentGuid = '{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}';
        final fb4Config = tcpConfig.copyWith(
          serverVersionHint: FirebirdServerVersionHint.v40,
        );

        when(
          () => processService.run(
            executable: 'isql',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          final iIndex = args.indexOf('-i');
          if (iIndex >= 0 && iIndex + 1 < args.length) {
            final scriptPath = args[iIndex + 1];
            final script = await File(scriptPath).readAsString();
            if (script.contains(r'RDB$BACKUP_HISTORY')) {
              return const rd.Success(
                ProcessResult(
                  exitCode: 0,
                  stdout: '$parentGuid\n',
                  stderr: '',
                  duration: Duration(milliseconds: 1),
                ),
              );
            }
          }
          return const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'isql default stub skips MON path',
              duration: Duration(milliseconds: 1),
            ),
          );
        });

        when(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          final bIndex = args.indexOf('-B');
          expect(bIndex, greaterThanOrEqualTo(0));
          expect(args[bIndex + 1], parentGuid);
          expect(args, isNot(contains('1')));
          final outPath = args.last;
          await File(outPath).writeAsBytes(List<int>.filled(10, 1));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 2),
            ),
          );
        });

        final result = await service.executeBackup(
          config: fb4Config,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-fb4-guid',
            backupType: BackupType.differential,
          ),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => processService.run(
            executable: 'isql',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(greaterThanOrEqualTo(1));
      },
    );

    test(
      r'executeBackup FB4 differential fails when RDB$BACKUP_HISTORY has no parent GUID',
      () async {
        final fb4Config = tcpConfig.copyWith(
          serverVersionHint: FirebirdServerVersionHint.v40,
        );

        when(
          () => processService.run(
            executable: 'isql',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          final iIndex = args.indexOf('-i');
          if (iIndex >= 0 && iIndex + 1 < args.length) {
            final scriptPath = args[iIndex + 1];
            final script = await File(scriptPath).readAsString();
            if (script.contains(r'RDB$BACKUP_HISTORY')) {
              return const rd.Success(
                ProcessResult(
                  exitCode: 0,
                  stdout: '\n',
                  stderr: '',
                  duration: Duration(milliseconds: 1),
                ),
              );
            }
          }
          return const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'isql default stub',
              duration: Duration(milliseconds: 1),
            ),
          );
        });

        final result = await service.executeBackup(
          config: fb4Config,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-fb4-no-guid',
            backupType: BackupType.differential,
          ),
        );

        expect(result.isError(), isTrue);
        verifyNever(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        );
      },
    );

    test('executeBackup differential override runs nbackup -B 2', () async {
      when(
        () => processService.run(
          executable: 'nbackup',
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.namedArguments[#arguments]! as List<String>;
        expect(args, contains('-B'));
        expect(args, contains('2'));
        final outPath = args.last;
        expect(outPath, contains('_nbackup_B2_'));
        expect(outPath, endsWith('.nbk'));
        await File(outPath).writeAsBytes(List<int>.filled(16, 2));
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: '',
            stderr: '',
            duration: Duration(milliseconds: 3),
          ),
        );
      });

      await File(p.join(tempDir.path, 'app_full_seed.nbk')).writeAsString('x');
      await File(
        p.join(tempDir.path, 'app_nbackup_B1_seed.nbk'),
      ).writeAsString('x');

      final result = await service.executeBackup(
        config: tcpConfig,
        context: BackupExecutionContext(
          outputDirectory: tempDir.path,
          scheduleId: 'sched-b2',
          backupType: BackupType.differential,
          firebirdNbackupPhysicalLevel: 2,
        ),
      );

      expect(result.isSuccess(), isTrue);
    });

    test(
      'executeBackup differential override B2 fails without B1 chain file',
      () async {
        await File(
          p.join(tempDir.path, 'app_full_seed.nbk'),
        ).writeAsString('x');

        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-b2-missing-b1',
            backupType: BackupType.differential,
            firebirdNbackupPhysicalLevel: 2,
          ),
        );

        expect(result.isError(), isTrue);
        verifyNever(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        );
      },
    );

    test(
      'executeBackup rejects nbackup physical level override on full single',
      () async {
        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-gbak-ov',
            backupType: BackupType.fullSingle,
            firebirdNbackupPhysicalLevel: 1,
          ),
        );

        expect(result.isError(), isTrue);
        verifyNever(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        );
      },
    );

    test(
      'executeBackup rejects nbackup override incompatible with full physical',
      () async {
        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-full-b1',
            firebirdNbackupPhysicalLevel: 1,
          ),
        );

        expect(result.isError(), isTrue);
        verifyNever(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        );
      },
    );

    test(
      'executeBackup differential fails without level-0 nbackup in output dir',
      () async {
        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-no-l0',
            backupType: BackupType.differential,
          ),
        );

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (Object failure) {
            expect(failure, isA<ValidationFailure>());
            final vf = failure as ValidationFailure;
            expect(vf.message, contains('app_full_'));
            expect(vf.message, contains('.nbk'));
          },
        );
        verifyNever(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        );
      },
    );

    test(
      'executeBackup log runs nbackup -B 1 and sets executedBackupType',
      () async {
        when(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          expect(args, contains('1'));
          final outPath = args.last;
          await File(outPath).writeAsBytes(List<int>.filled(24, 3));
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
              duration: Duration(milliseconds: 3),
            ),
          );
        });

        await File(
          p.join(tempDir.path, 'app_full_seed.nbk'),
        ).writeAsString('x');

        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-log',
            backupType: BackupType.log,
          ),
        );

        expect(result.isSuccess(), isTrue);
        result.fold(
          (r) {
            expect(r.executedBackupType, BackupType.differential);
          },
          (_) => fail('expected success'),
        );
      },
    );

    test('executeBackup rejects converted full single type', () async {
      final result = await service.executeBackup(
        config: tcpConfig,
        context: BackupExecutionContext(
          outputDirectory: tempDir.path,
          scheduleId: 'sched-cfs',
          backupType: BackupType.convertedFullSingle,
        ),
      );

      expect(result.isError(), isTrue);
      verifyNever(
        () => processService.run(
          executable: 'nbackup',
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      );
    });

    test(
      'testConnection skips gstat when embedded FB3 on Windows lacks client library path',
      skip: !Platform.isWindows,
      () async {
        final dbPath = p.join(tempDir.path, 'tc_emb.fdb');
        await File(dbPath).writeAsBytes(<int>[1]);
        final cfg = FirebirdConfig(
          name: 'tc',
          host: 'localhost',
          databaseFile: dbPath,
          username: 'u',
          password: 'p',
          useEmbedded: true,
          serverVersionHint: FirebirdServerVersionHint.v30,
        );

        final result = await service.testConnection(cfg);

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (Object f) {
            expect(f, isA<ValidationFailure>());
            expect(
              (f as ValidationFailure).message,
              contains('Client library path'),
            );
          },
        );
        verifyNever(
          () => processService.run(
            executable: 'gstat',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        );
      },
    );

    test('testConnection succeeds when gstat exits zero', () async {
      when(
        () => processService.run(
          executable: 'gstat',
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.namedArguments[#arguments]! as List<String>;
        expect(args, contains('-h'));
        expect(args, contains('srv.example/3050:/data/app.fdb'));
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: 'header ok',
            stderr: '',
            duration: Duration(milliseconds: 3),
          ),
        );
      });

      final result = await service.testConnection(tcpConfig);
      expect(result.getOrNull(), isTrue);
    });

    test(
      'getGstatHeaderVersionHint returns ODS family when header contains ODS',
      () async {
        when(
          () => processService.run(
            executable: 'gstat',
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
              stdout:
                  'Database header page information:\n'
                  '   ODS version    12.0\n',
              stderr: '',
              duration: Duration(milliseconds: 2),
            ),
          ),
        );

        final result = await service.getGstatHeaderVersionHint(tcpConfig);
        expect(result.getOrNull(), 'ODS 12.0 (Firebird 3.x)');
      },
    );

    test(
      'getGstatHeaderVersionHint returns empty string when ODS and WI-V '
      'absent',
      () async {
        when(
          () => processService.run(
            executable: 'gstat',
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
              stdout: 'header ok',
              stderr: '',
              duration: Duration(milliseconds: 1),
            ),
          ),
        );

        final result = await service.getGstatHeaderVersionHint(tcpConfig);
        expect(result.getOrNull(), '');
      },
    );

    test(
      'getGstatHeaderVersionHint returns WI-V token when ODS absent',
      () async {
        when(
          () => processService.run(
            executable: 'gstat',
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
              stdout: 'Engine WI-V4.0.0.2943 Firebird 4.0',
              stderr: '',
              duration: Duration(milliseconds: 1),
            ),
          ),
        );

        final result = await service.getGstatHeaderVersionHint(tcpConfig);
        expect(result.getOrNull(), 'WI-V4.0.0.2943');
      },
    );

    test(
      'probeGstatHeaderConnection invokes gstat once and returns parsed '
      'versionHint',
      () async {
        when(
          () => processService.run(
            executable: 'gstat',
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
              stdout: '   ODS version    13.0\n',
              stderr: '',
              duration: Duration(milliseconds: 1),
            ),
          ),
        );

        final result = await service.probeGstatHeaderConnection(tcpConfig);
        expect(result.getOrNull()?.versionHint, 'ODS 13.0 (Firebird 4.x)');
        verify(
          () => processService.run(
            executable: 'gstat',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(1);
      },
    );

    test(
      'probeGstatHeaderConnection then getGstatHeaderVersionHint invokes '
      'gstat twice',
      () async {
        when(
          () => processService.run(
            executable: 'gstat',
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
              stdout: 'ODS version    11.1\n',
              stderr: '',
              duration: Duration(milliseconds: 1),
            ),
          ),
        );

        final probe = await service.probeGstatHeaderConnection(tcpConfig);
        expect(probe.getOrNull()?.versionHint, 'ODS 11.1 (Firebird 2.5)');

        final hint = await service.getGstatHeaderVersionHint(tcpConfig);
        expect(hint.getOrNull(), 'ODS 11.1 (Firebird 2.5)');

        verify(
          () => processService.run(
            executable: 'gstat',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(2);
      },
    );

    test(
      'testConnection maps ProcessService failure to ToolPathHelp for gstat',
      () async {
        when(
          () => processService.run(
            executable: 'gstat',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Failure(
            ValidationFailure(message: 'gstat: command not found'),
          ),
        );

        final result = await service.testConnection(tcpConfig);
        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (f) => expect(f, isA<ValidationFailure>()),
        );
      },
    );

    test(
      'testConnection surfaces AuthServer hint for undefined user/password',
      () async {
        when(
          () => processService.run(
            executable: 'gstat',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 2,
              stdout: '',
              stderr:
                  'Your user name and password are not defined. Ask your '
                  'database admin.',
              duration: Duration(milliseconds: 1),
            ),
          ),
        );

        final result = await service.testConnection(tcpConfig);
        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (f) {
            expect(f, isA<ValidationFailure>());
            expect(
              (f as ValidationFailure).message.toLowerCase(),
              contains('authserver'),
            );
          },
        );
      },
    );

    test(
      'executeBackup surfaces WireCrypt hint on incompatible wire encryption',
      () async {
        when(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          final outPath = args.last;
          await File(outPath).writeAsString('partial');
          return const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout:
                  'Incompatible wire encryption levels on client and '
                  'server',
              stderr: '',
              duration: Duration(milliseconds: 2),
            ),
          );
        });

        final result = await service.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-1',
          ),
        );

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (f) {
            expect(f, isA<BackupFailure>());
            expect(
              (f as BackupFailure).message.toLowerCase(),
              contains('wirecrypt'),
            );
          },
        );
      },
    );

    test(
      'getDatabaseSizeBytes uses isql MON estimate when isql succeeds',
      () async {
        when(
          () => processService.run(
            executable: 'isql',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          expect(args, contains('-password'));
          expect(args, contains('-i'));
          expect(args.last, 'srv.example/3050:/data/app.fdb');
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '\n\n999000\n',
              stderr: '',
              duration: Duration(milliseconds: 1),
            ),
          );
        });

        final result = await service.getDatabaseSizeBytes(
          config: tcpConfig,
        );
        expect(result.getOrNull(), 999000);
        verify(
          () => processService.run(
            executable: 'isql',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(1);
        verifyNever(
          () => processService.run(
            executable: 'gstat',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        );
      },
    );

    test(
      'getDatabaseSizeBytes falls back to gstat when isql output has no int',
      () async {
        when(
          () => processService.run(
            executable: 'isql',
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
              stdout: 'no numeric result here',
              stderr: '',
              duration: Duration(milliseconds: 1),
            ),
          ),
        );
        when(
          () => processService.run(
            executable: 'gstat',
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
              stdout: 'Page size: 2048\nData pages: 3\n',
              stderr: '',
              duration: Duration(milliseconds: 2),
            ),
          ),
        );

        final result = await service.getDatabaseSizeBytes(
          config: tcpConfig,
        );
        expect(result.getOrNull(), 2048 * 3);
      },
    );

    test('getDatabaseSizeBytes parses page size and data pages', () async {
      when(
        () => processService.run(
          executable: 'gstat',
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
            stdout: '''
Database header page information:
Page size: 4096
Data pages: 10
''',
            stderr: '',
            duration: Duration(milliseconds: 2),
          ),
        ),
      );

      final result = await service.getDatabaseSizeBytes(config: tcpConfig);
      expect(result.getOrNull(), 4096 * 10);
    });

    test('getDatabaseSizeBytes fails when gstat output lacks stats', () async {
      when(
        () => processService.run(
          executable: 'gstat',
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
            stdout: 'no stats here',
            stderr: '',
            duration: Duration(milliseconds: 1),
          ),
        ),
      );

      final result = await service.getDatabaseSizeBytes(config: tcpConfig);
      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<BackupFailure>()),
      );
    });

    test(
      'getDatabaseSizeBytes uses local file when embedded and gstat cannot parse',
      () async {
        final fdbPath = p.join(tempDir.path, 'embedded_probe.fdb');
        await File(fdbPath).writeAsBytes(
          List<int>.generate(88, (i) => i % 256),
        );
        final embedded = FirebirdConfig(
          name: 'emb',
          host: 'localhost',
          databaseFile: fdbPath,
          username: 'u',
          password: 'p',
          useEmbedded: true,
        );
        when(
          () => processService.run(
            executable: 'gstat',
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
              stdout: 'no stats here',
              stderr: '',
              duration: Duration(milliseconds: 1),
            ),
          ),
        );

        final result = await service.getDatabaseSizeBytes(
          config: embedded,
        );
        expect(result.getOrNull(), 88);
        verify(
          () => processService.run(
            executable: 'isql',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(1);
        verify(
          () => processService.run(
            executable: 'gstat',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(1);
      },
    );

    test('alias uses host/port:alias in gstat arguments', () async {
      final aliasCfg = FirebirdConfig(
        name: 'a',
        host: 'fb-srv',
        databaseFile: '/ignored/unless_alias_empty.fdb',
        username: 'u',
        password: 'p',
        aliasName: 'mydb',
      );
      when(
        () => processService.run(
          executable: 'gstat',
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.namedArguments[#arguments]! as List<String>;
        expect(args.last, 'fb-srv/3050:mydb');
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: 'Page size: 8192\nData pages: 2\n',
            stderr: '',
            duration: Duration(milliseconds: 1),
          ),
        );
      });

      final result = await service.getDatabaseSizeBytes(config: aliasCfg);
      expect(result.getOrNull(), 8192 * 2);
    });

    group('gbak -z runtime probe (serverVersionHint auto)', () {
      test(
        'enriches BackupMetrics.firebirdVersion when gbak -z returns WI-V',
        () async {
          final probed = FirebirdBackupService(processService);
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
            final exe = invocation.namedArguments[#executable]! as String;
            final args = invocation.namedArguments[#arguments]! as List<String>;
            if (exe == 'gbak' && args.length == 1 && args.first == '-z') {
              return const rd.Success(
                ProcessResult(
                  exitCode: 0,
                  stdout: 'gbak version WI-V4.0.0.2943 Firebird 4.0',
                  stderr: '',
                  duration: Duration(milliseconds: 1),
                ),
              );
            }
            if (exe == 'gbak' && args.contains('-b')) {
              await File(args.last).writeAsBytes(List<int>.filled(20, 9));
              return const rd.Success(
                ProcessResult(
                  exitCode: 0,
                  stdout: '',
                  stderr: '',
                  duration: Duration(milliseconds: 2),
                ),
              );
            }
            fail('unexpected run: $exe $args');
          });

          final result = await probed.executeBackup(
            config: tcpConfig,
            context: BackupExecutionContext(
              outputDirectory: tempDir.path,
              scheduleId: 'sched-z-probe',
              backupType: BackupType.fullSingle,
            ),
          );

          expect(result.isSuccess(), isTrue);
          result.fold(
            (r) {
              expect(
                r.metrics!.flags.firebirdVersion,
                'auto|WI-V4.0.0.2943',
              );
            },
            (_) => fail('expected success'),
          );
          verify(
            () => processService.run(
              executable: 'gbak',
              arguments: const <String>['-z'],
              workingDirectory: any(named: 'workingDirectory'),
              environment: any(named: 'environment'),
              timeout: any(named: 'timeout'),
              tag: any(named: 'tag'),
            ),
          ).called(1);
        },
      );

      test(
        'gbak -z cache is per host:port:target — different hosts probe twice',
        () async {
          final probed = FirebirdBackupService(processService);
          var zProbeCount = 0;
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
            final exe = invocation.namedArguments[#executable]! as String;
            final args = invocation.namedArguments[#arguments]! as List<String>;
            if (exe == 'gbak' && args.length == 1 && args.first == '-z') {
              zProbeCount++;
              return const rd.Success(
                ProcessResult(
                  exitCode: 0,
                  stdout: 'WI-V4.0.0.1',
                  stderr: '',
                  duration: Duration(milliseconds: 1),
                ),
              );
            }
            if (exe == 'gbak' && args.contains('-b')) {
              await File(args.last).writeAsBytes(List<int>.filled(12, 1));
              return const rd.Success(
                ProcessResult(
                  exitCode: 0,
                  stdout: '',
                  stderr: '',
                  duration: Duration(milliseconds: 1),
                ),
              );
            }
            if (exe == 'nbackup') {
              await File(args.last).writeAsBytes(List<int>.filled(12, 1));
              return const rd.Success(
                ProcessResult(
                  exitCode: 0,
                  stdout: '',
                  stderr: '',
                  duration: Duration(milliseconds: 1),
                ),
              );
            }
            fail('unexpected: $exe $args');
          });

          final cfgA = tcpConfig.copyWith(host: 'host-a.example');
          final cfgB = tcpConfig.copyWith(host: 'host-b.example');
          final ctx = BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-z-host',
            backupType: BackupType.fullSingle,
          );
          await probed.executeBackup(config: cfgA, context: ctx);
          await probed.executeBackup(config: cfgB, context: ctx);

          expect(zProbeCount, 2);
        },
      );

      test('caches gbak -z: second backup does not invoke -z again', () async {
        final probed = FirebirdBackupService(processService);
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
          final exe = invocation.namedArguments[#executable]! as String;
          final args = invocation.namedArguments[#arguments]! as List<String>;
          if (exe == 'gbak' && args.length == 1 && args.first == '-z') {
            return const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: 'WI-V3.0.5.1',
                stderr: '',
                duration: Duration(milliseconds: 1),
              ),
            );
          }
          if (exe == 'gbak' && args.contains('-b')) {
            await File(args.last).writeAsBytes(List<int>.filled(18, 8));
            return const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: '',
                stderr: '',
                duration: Duration(milliseconds: 2),
              ),
            );
          }
          fail('unexpected run: $exe $args');
        });

        final ctx = BackupExecutionContext(
          outputDirectory: tempDir.path,
          scheduleId: 'sched-z-cache',
          backupType: BackupType.fullSingle,
        );
        await probed.executeBackup(config: tcpConfig, context: ctx);
        await probed.executeBackup(config: tcpConfig, context: ctx);

        verify(
          () => processService.run(
            executable: 'gbak',
            arguments: const <String>['-z'],
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).called(1);
      });

      test('runs gbak -z before nbackup when hint is auto', () async {
        final probed = FirebirdBackupService(processService);
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
          final exe = invocation.namedArguments[#executable]! as String;
          final args = invocation.namedArguments[#arguments]! as List<String>;
          if (exe == 'gbak' && args.length == 1 && args.first == '-z') {
            return const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: 'tool WI-V3.0.10',
                stderr: '',
                duration: Duration(milliseconds: 1),
              ),
            );
          }
          if (exe == 'nbackup') {
            final outPath = args.last;
            await File(outPath).writeAsBytes(List<int>.filled(40, 3));
            return const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: '',
                stderr: '',
                duration: Duration(milliseconds: 2),
              ),
            );
          }
          fail('unexpected run: $exe $args');
        });

        final result = await probed.executeBackup(
          config: tcpConfig,
          context: BackupExecutionContext(
            outputDirectory: tempDir.path,
            scheduleId: 'sched-z-nbackup',
          ),
        );

        expect(result.isSuccess(), isTrue);
        result.fold(
          (r) {
            expect(r.metrics!.flags.tool, 'nbackup');
            expect(r.metrics!.flags.firebirdVersion, 'auto|WI-V3.0.10');
          },
          (_) => fail('expected success'),
        );
        verifyInOrder([
          () => processService.run(
            executable: 'gbak',
            arguments: const <String>['-z'],
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            workingDirectory: any(named: 'workingDirectory'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ]);
      });
    });

    group('listDatabases', () {
      test('returns Failure when connection spec cannot be built', () async {
        final cfg = tcpConfig.copyWith(
          databaseFile: '',
          aliasName: '',
        );
        final r = await service.listDatabases(config: cfg);
        expect(r.isError(), isTrue);
      });

      test('returns MON database name when isql stdout contains it', () async {
        reset(processService);
        when(
          () => processService.run(
            executable: 'isql',
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
              stdout: 'QUIT\n/srv/db/warehouse.fdb\n',
              stderr: '',
              duration: Duration(milliseconds: 1),
            ),
          ),
        );

        final r = await service.listDatabases(config: tcpConfig);
        expect(r.isSuccess(), isTrue);
        r.fold(
          (names) => expect(names, ['/srv/db/warehouse.fdb']),
          (_) => fail('expected success'),
        );
      });

      test(
        'falls back to databaseFile when isql yields no name line',
        () async {
          reset(processService);
          when(
            () => processService.run(
              executable: 'isql',
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
                stdout: 'SET HEADING OFF;\nQUIT\n',
                stderr: '',
                duration: Duration(milliseconds: 1),
              ),
            ),
          );

          final r = await service.listDatabases(config: tcpConfig);
          expect(r.isSuccess(), isTrue);
          r.fold(
            (names) => expect(names, ['/data/app.fdb']),
            (_) => fail('expected success'),
          );
        },
      );

      test('falls back to alias when MON parse empty and alias set', () async {
        reset(processService);
        when(
          () => processService.run(
            executable: 'isql',
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
              stdout: 'QUIT\n',
              stderr: '',
              duration: Duration(milliseconds: 1),
            ),
          ),
        );

        final cfg = tcpConfig.copyWith(
          databaseFile: '',
          aliasName: 'myalias',
        );
        final r = await service.listDatabases(config: cfg);
        expect(r.isSuccess(), isTrue);
        r.fold(
          (names) => expect(names, ['myalias']),
          (_) => fail('expected success'),
        );
      });

      test('returns Failure when isql exits with error', () async {
        reset(processService);
        when(
          () => processService.run(
            executable: 'isql',
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
              stderr: 'connection reset',
              duration: Duration(milliseconds: 1),
            ),
          ),
        );

        final r = await service.listDatabases(config: tcpConfig);
        expect(r.isError(), isTrue);
      });
    });
  });
}
