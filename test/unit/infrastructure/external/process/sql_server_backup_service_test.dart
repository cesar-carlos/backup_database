import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/process/sql_server_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockProcessService extends Mock implements ProcessService {}

void main() {
  late _MockProcessService processService;
  late SqlServerBackupService service;
  late SqlServerConfig sqlAuthConfig;
  late SqlServerConfig windowsAuthConfig;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(<String, String>{});
    registerFallbackValue(const Duration(seconds: 1));
  });

  setUp(() async {
    processService = _MockProcessService();
    service = SqlServerBackupService(processService);
    tempDir = await Directory.systemTemp.createTemp(
      'sql_server_backup_service_',
    );

    sqlAuthConfig = SqlServerConfig(
      id: 'cfg-1',
      name: 'SQL Auth',
      server: 'localhost',
      database: DatabaseName('appdb'),
      username: 'sa',
      password: 'secret',
      port: PortNumber(1433),
    );

    windowsAuthConfig = SqlServerConfig(
      id: 'cfg-2',
      name: 'Windows Auth',
      server: 'localhost',
      database: DatabaseName('appdb'),
      username: 'ignored',
      password: 'ignored',
      port: PortNumber(1433),
      useWindowsAuth: true,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SqlServerBackupService', () {
    test('SQL Auth usa SQLCMDPASSWORD e nao envia -P nos argumentos', () async {
      when(
        () => processService.run(
          executable: 'sqlcmd',
          arguments: any(named: 'arguments'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: 'ok',
            stderr: '',
            duration: Duration(milliseconds: 10),
          ),
        ),
      );

      final result = await service.testConnection(sqlAuthConfig);
      expect(result.isSuccess(), isTrue);

      final captured = verify(
        () => processService.run(
          executable: 'sqlcmd',
          arguments: captureAny(named: 'arguments'),
          environment: captureAny(named: 'environment'),
          timeout: any(named: 'timeout'),
        ),
      ).captured;

      final args = captured[0] as List<String>;
      final env = captured[1] as Map<String, String>?;

      expect(args.contains('-U'), isTrue);
      expect(args.contains('-P'), isFalse);
      expect(env?['SQLCMDPASSWORD'], 'secret');
    });

    test('Windows Auth força -E e nao envia SQLCMDPASSWORD', () async {
      when(
        () => processService.run(
          executable: 'sqlcmd',
          arguments: any(named: 'arguments'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: 'ok',
            stderr: '',
            duration: Duration(milliseconds: 10),
          ),
        ),
      );

      final result = await service.testConnection(windowsAuthConfig);
      expect(result.isSuccess(), isTrue);

      final captured = verify(
        () => processService.run(
          executable: 'sqlcmd',
          arguments: captureAny(named: 'arguments'),
          environment: captureAny(named: 'environment'),
          timeout: any(named: 'timeout'),
        ),
      ).captured;

      final args = captured[0] as List<String>;
      final env = captured[1] as Map<String, String>?;

      expect(args.contains('-E'), isTrue);
      expect(args.contains('-U'), isFalse);
      expect(env, anyOf(isNull, isEmpty));
    });

    test('verifyPolicy strict falha quando VERIFYONLY retorna erro', () async {
      when(
        () => processService.run(
          executable: 'sqlcmd',
          arguments: any(named: 'arguments'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.namedArguments[#arguments]! as List<String>;
        final query = _argumentValue(args, '-Q') ?? '';

        if (query.startsWith('BACKUP ')) {
          final backupPath = _extractFirstDiskPath(query)!;
          await File(backupPath).create(recursive: true);
          await File(backupPath).writeAsString('backup-bytes');

          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'BACKUP DATABASE successfully processed',
              stderr: '',
              duration: Duration(milliseconds: 20),
            ),
          );
        }

        if (query.startsWith('RESTORE VERIFYONLY')) {
          return const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'VERIFY failed',
              duration: Duration(milliseconds: 10),
            ),
          );
        }

        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: 'ok',
            stderr: '',
            duration: Duration(milliseconds: 10),
          ),
        );
      });

      final result = await service.executeBackup(
        config: sqlAuthConfig,
        outputDirectory: tempDir.path,
        scheduleId: 's-1',
        verifyAfterBackup: true,
        verifyPolicy: VerifyPolicy.strict,
        backupTimeout: const Duration(minutes: 7),
        verifyTimeout: const Duration(minutes: 3),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<BackupFailure>());

      verify(
        () => processService.run(
          executable: 'sqlcmd',
          arguments: any(named: 'arguments'),
          environment: any(named: 'environment'),
          timeout: const Duration(minutes: 7),
          tag: any(named: 'tag'),
        ),
      ).called(1);

      verify(
        () => processService.run(
          executable: 'sqlcmd',
          arguments: any(named: 'arguments'),
          environment: any(named: 'environment'),
          timeout: const Duration(minutes: 3),
          tag: any(named: 'tag'),
        ),
      ).called(1);
    });

    test(
      'backup log falha no pre-check quando recovery model nao permite',
      () async {
        when(
          () => processService.run(
            executable: 'sqlcmd',
            arguments: any(named: 'arguments'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          final query = _argumentValue(args, '-Q') ?? '';

          if (query.contains('recovery_model_desc')) {
            return const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: 'SIMPLE\n',
                stderr: '',
                duration: Duration(milliseconds: 10),
              ),
            );
          }

          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'ok',
              stderr: '',
              duration: Duration(milliseconds: 10),
            ),
          );
        });

        final result = await service.executeBackup(
          config: sqlAuthConfig,
          outputDirectory: tempDir.path,
          scheduleId: 's-1',
          backupType: BackupType.log,
        );

        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<ValidationFailure>());

        final backupCalls = verify(
          () => processService.run(
            executable: 'sqlcmd',
            arguments: captureAny(named: 'arguments'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
            tag: any(named: 'tag'),
          ),
        ).captured;

        final queries = backupCalls
            .whereType<List<String>>()
            .map((args) => _argumentValue(args, '-Q') ?? '')
            .toList();

        expect(queries.any((q) => q.startsWith('BACKUP LOG')), isFalse);
      },
    );

    test('gera SQL com tuning e escape de identificador', () async {
      final cfg = sqlAuthConfig.copyWith(
        database: DatabaseName('db]name'),
      );

      when(
        () => processService.run(
          executable: 'sqlcmd',
          arguments: any(named: 'arguments'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.namedArguments[#arguments]! as List<String>;
        final query = _argumentValue(args, '-Q') ?? '';

        if (query.startsWith('BACKUP ')) {
          final backupPath = _extractFirstDiskPath(query)!;
          await File(backupPath).create(recursive: true);
          await File(backupPath).writeAsString('backup-bytes');
        }

        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: 'ok',
            stderr: '',
            duration: Duration(milliseconds: 10),
          ),
        );
      });

      final result = await service.executeBackup(
        config: cfg,
        outputDirectory: tempDir.path,
        scheduleId: 's-1',
        enableChecksum: true,
        sqlServerBackupOptions: const SqlServerBackupOptions(
          compression: true,
          maxTransferSize: 4194304,
          bufferCount: 50,
          blockSize: 65536,
          statsPercent: 5,
        ),
      );

      expect(result.isSuccess(), isTrue);

      final captured = verify(
        () => processService.run(
          executable: 'sqlcmd',
          arguments: captureAny(named: 'arguments'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).captured;

      final backupArgs = captured.whereType<List<String>>().firstWhere((args) {
        final query = _argumentValue(args, '-Q') ?? '';
        return query.startsWith('BACKUP ');
      });

      final query = _argumentValue(backupArgs, '-Q') ?? '';
      expect(query.contains('[db]]name]'), isTrue);
      expect(query.contains('CHECKSUM'), isTrue);
      expect(query.contains('STOP_ON_ERROR'), isTrue);
      expect(query.contains('COMPRESSION'), isTrue);
      expect(query.contains('MAXTRANSFERSIZE = 4194304'), isTrue);
      expect(query.contains('BUFFERCOUNT = 50'), isTrue);
      expect(query.contains('BLOCKSIZE = 65536'), isTrue);
      expect(query.contains('STATS = 5'), isTrue);
    });
  });
}

String? _argumentValue(List<String> args, String key) {
  final index = args.indexOf(key);
  if (index < 0 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}

String? _extractFirstDiskPath(String query) {
  final match = RegExp("TO DISK = N'([^']+)'").firstMatch(query);
  return match?.group(1);
}
