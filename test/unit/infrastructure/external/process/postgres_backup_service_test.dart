import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/external/process/postgres_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockProcessService extends Mock implements ProcessService {}

void main() {
  late _MockProcessService processService;
  late PostgresBackupService service;
  late Directory tempDir;
  late PostgresConfig config;

  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(<String, String>{});
    registerFallbackValue(const Duration(seconds: 1));
  });

  setUp(() async {
    processService = _MockProcessService();
    service = PostgresBackupService(processService);
    tempDir = await Directory.systemTemp.createTemp('postgres_backup_service_');
    config = PostgresConfig(
      id: 'cfg-1',
      name: 'Postgres Local',
      host: 'localhost',
      port: PortNumber(5432),
      database: DatabaseName('appdb'),
      username: 'postgres',
      password: 'secret',
    );
  });

  tearDown(() async {
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

  group('PostgresBackupService', () {
    test(
      'differential faz fallback para full quando nao encontra base anterior',
      () async {
        when(
          () => processService.run(
            executable: 'pg_basebackup',
            arguments: any(named: 'arguments'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          final arguments =
              invocation.namedArguments[#arguments]! as List<String>;
          final targetDirectory = _argumentValue(arguments, '-D');
          expect(targetDirectory, isNotNull);
          await Directory(targetDirectory!).create(recursive: true);
          await File(
            '$targetDirectory${Platform.pathSeparator}backup_manifest',
          ).writeAsString('manifest');

          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'ok',
              stderr: '',
              duration: Duration(milliseconds: 20),
            ),
          );
        });

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          backupType: BackupType.differential,
        );

        result.fold(
          (value) {
            expect(value.backupPath, contains('_full_'));
            expect(value.backupPath, isNot(contains('_incremental_')));
            expect(value.fileSize, greaterThan(0));
          },
          (failure) => fail('Esperava sucesso, recebeu erro: $failure'),
        );
      },
    );

    test('log sem novos WAL retorna sucesso com tamanho zero', () async {
      when(
        () => processService.run(
          executable: 'psql',
          arguments: any(named: 'arguments'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.namedArguments[#arguments]! as List<String>;
        final query = _argumentValue(args, '-c') ?? '';
        if (query.contains('SELECT pg_current_wal_lsn()')) {
          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: '0/16B6A30\n',
              stderr: '',
              duration: Duration(milliseconds: 10),
            ),
          );
        }

        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: 'replica|10|10|true\n',
            stderr: '',
            duration: Duration(milliseconds: 10),
          ),
        );
      });

      when(
        () => processService.run(
          executable: 'pg_receivewal',
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
            duration: Duration(milliseconds: 50),
          ),
        ),
      );

      final result = await service.executeBackup(
        config: config,
        outputDirectory: tempDir.path,
        backupType: BackupType.log,
      );

      if (result.isError()) {
        fail('Esperava sucesso, recebeu erro: ${result.exceptionOrNull()}');
      }
      final value = result.getOrNull()!;
      expect(value.fileSize, 0);

      final metadata = File(
        '${value.backupPath}${Platform.pathSeparator}wal_capture_info.txt',
      );
      expect(await metadata.exists(), isTrue);
      final content = await metadata.readAsString();
      expect(content, contains('captured_segments=0'));
      expect(content, contains('captured_bytes=0'));
      expect(content, contains('had_new_wal=false'));

      final captures = verify(
        () => processService.run(
          executable: 'pg_receivewal',
          arguments: captureAny(named: 'arguments'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
        ),
      ).captured;
      final args = captures.single as List<String>;
      expect(args.where((a) => a.startsWith('--slot=')).isEmpty, isTrue);
    });

    test('testConnection reporta erro de psql ausente corretamente', () async {
      when(
        () => processService.run(
          executable: 'psql',
          arguments: any(named: 'arguments'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => const rd.Success(
          ProcessResult(
            exitCode: 1,
            stdout: '',
            stderr:
                "'psql' is not recognized as an internal or external command",
            duration: Duration(milliseconds: 10),
          ),
        ),
      );

      final result = await service.testConnection(config);
      result.fold(
        (value) => fail('Esperava falha, recebeu sucesso: $value'),
        (failure) {
          expect(failure, isA<ValidationFailure>());
          expect((failure as ValidationFailure).message, contains('psql'));
        },
      );
    });

    test(
      'log reporta erro de pg_receivewal ausente com mensagem especifica',
      () async {
        when(
          () => processService.run(
            executable: 'psql',
            arguments: any(named: 'arguments'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          final args = invocation.namedArguments[#arguments]! as List<String>;
          final query = _argumentValue(args, '-c') ?? '';
          if (query.contains('SELECT pg_current_wal_lsn()')) {
            return const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: '0/16B6A30\n',
                stderr: '',
                duration: Duration(milliseconds: 10),
              ),
            );
          }

          return const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'replica|10|10|true\n',
              stderr: '',
              duration: Duration(milliseconds: 10),
            ),
          );
        });

        when(
          () => processService.run(
            executable: 'pg_receivewal',
            arguments: any(named: 'arguments'),
            environment: any(named: 'environment'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr:
                  "'pg_receivewal' is not recognized as an internal or external command",
              duration: Duration(milliseconds: 10),
            ),
          ),
        );

        final result = await service.executeBackup(
          config: config,
          outputDirectory: tempDir.path,
          backupType: BackupType.log,
        );

        result.fold(
          (value) => fail('Esperava falha, recebeu sucesso: $value'),
          (failure) {
            expect(failure, isA<BackupFailure>());
            expect(
              (failure as BackupFailure).message,
              contains('pg_receivewal'),
            );
          },
        );
      },
    );
  });
}

String? _argumentValue(List<String> args, String key) {
  final index = args.indexOf(key);
  if (index < 0 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}
