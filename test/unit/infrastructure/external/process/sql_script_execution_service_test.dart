import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/process/sql_script_execution_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockProcessService extends Mock implements ProcessService {}

void main() {
  late _MockProcessService processService;
  late SqlScriptExecutionService service;

  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(<String, String>{});
    registerFallbackValue(const Duration(seconds: 1));
  });

  setUp(() {
    processService = _MockProcessService();
    service = SqlScriptExecutionService(processService);
  });

  group('SqlScriptExecutionService', () {
    test('executeScript rejects Firebird when config is null', () async {
      final result = await service.executeScript(
        databaseType: DatabaseType.firebird,
        sqlServerConfig: null,
        sybaseConfig: null,
        postgresConfig: null,
        firebirdConfig: null,
        script: r'select 1 from rdb$database;',
      );

      expect(result.isError(), isTrue);
      final Object? err = result.exceptionOrNull();
      expect(err, isA<ValidationFailure>());
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
      'executeScript rejects Firebird embedded with empty database path',
      () async {
        final config = FirebirdConfig(
          name: 'fb',
          host: 'localhost',
          databaseFile: '   ',
          username: 'sysdba',
          password: 'x',
          useEmbedded: true,
        );

        final result = await service.executeScript(
          databaseType: DatabaseType.firebird,
          sqlServerConfig: null,
          sybaseConfig: null,
          postgresConfig: null,
          firebirdConfig: config,
          script: r'select 1 from rdb$database;',
        );

        expect(result.isError(), isTrue);
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

    test('executeScript invokes isql for Firebird TCP config', () async {
      final config = FirebirdConfig(
        name: 'fb',
        host: 'srv.example',
        databaseFile: '/data/app.fdb',
        username: 'sysdba',
        password: 'masterkey',
        port: PortNumber(3050),
      );

      when(
        () => processService.run(
          executable: any(named: 'executable'),
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
            stdout: '',
            stderr: '',
            duration: Duration.zero,
          ),
        ),
      );

      final result = await service.executeScript(
        databaseType: DatabaseType.firebird,
        sqlServerConfig: null,
        sybaseConfig: null,
        postgresConfig: null,
        firebirdConfig: config,
        script: r'select 1 from rdb$database;',
      );

      expect(result.isSuccess(), isTrue);

      final verification = verify(
        () => processService.run(
          executable: 'isql',
          arguments: captureAny(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      );
      verification.called(1);

      final captured = verification.captured;
      final arguments = captured.first as List<String>;
      expect(arguments, contains('-user'));
      expect(arguments, contains('sysdba'));
      expect(arguments, contains('-password'));
      expect(arguments, contains('masterkey'));
      expect(arguments, contains('-i'));
      expect(arguments, contains('srv.example/3050:/data/app.fdb'));
    });
  });
}
