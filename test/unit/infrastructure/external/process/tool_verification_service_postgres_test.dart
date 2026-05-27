import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/process/tool_verification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockProcessService extends Mock implements ProcessService {}

void main() {
  late _MockProcessService processService;
  late ToolVerificationService service;

  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 1));
  });

  setUp(() {
    processService = _MockProcessService();
    service = ToolVerificationService(processService);
  });

  ProcessResult ok({String stdout = 'psql (PostgreSQL) 17.0'}) => ProcessResult(
    exitCode: 0,
    stdout: stdout,
    stderr: '',
    duration: const Duration(milliseconds: 5),
  );

  ProcessResult missing() => const ProcessResult(
    exitCode: 1,
    stdout: '',
    stderr: "'pg_dump' is not recognized as an internal or external command",
    duration: Duration(milliseconds: 2),
  );

  void mockTool(String executable, ProcessResult result) {
    when(
      () => processService.run(
        executable: executable,
        arguments: any(named: 'arguments'),
        timeout: any(named: 'timeout'),
      ),
    ).thenAnswer((_) async => rd.Success(result));
  }

  group('verifyPostgresTools', () {
    // Achado A.1 da auditoria: antes desse fix, PostgresConfigProvider não
    // chamava ToolVerificationService no save, então uma config podia ser
    // criada sem os binários instalados e o usuário só descobria na
    // primeira execução de backup.
    test(
      'sucesso quando psql, pg_basebackup, pg_dump e pg_receivewal estão '
      'disponíveis (e pg_verifybackup também)',
      () async {
        mockTool('psql', ok());
        mockTool('pg_basebackup', ok());
        mockTool('pg_dump', ok());
        mockTool('pg_receivewal', ok());
        mockTool('pg_verifybackup', ok());

        final result = await service.verifyPostgresTools();
        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), isTrue);

        for (final tool in const [
          'psql',
          'pg_basebackup',
          'pg_dump',
          'pg_receivewal',
          'pg_verifybackup',
        ]) {
          verify(
            () => processService.run(
              executable: tool,
              arguments: any(
                named: 'arguments',
                that: equals(const ['--version']),
              ),
              timeout: any(named: 'timeout'),
            ),
          ).called(1);
        }
      },
    );

    test(
      'pg_verifybackup ausente NÃO bloqueia (warning apenas), demais 4 OK',
      () async {
        mockTool('psql', ok());
        mockTool('pg_basebackup', ok());
        mockTool('pg_dump', ok());
        mockTool('pg_receivewal', ok());
        mockTool('pg_verifybackup', missing());

        final result = await service.verifyPostgresTools();
        expect(result.isSuccess(), isTrue);
      },
    );

    test(
      'falha curto-circuita: psql ausente NÃO tenta pg_basebackup/pg_dump/pg_receivewal',
      () async {
        mockTool('psql', missing());
        mockTool('pg_basebackup', ok());
        mockTool('pg_dump', ok());
        mockTool('pg_receivewal', ok());

        final result = await service.verifyPostgresTools();
        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<ValidationFailure>());
        expect(
          (result.exceptionOrNull()! as ValidationFailure).message,
          contains('psql'),
        );

        verify(
          () => processService.run(
            executable: 'psql',
            arguments: any(named: 'arguments'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
        for (final tool in const [
          'pg_basebackup',
          'pg_dump',
          'pg_receivewal',
        ]) {
          verifyNever(
            () => processService.run(
              executable: tool,
              arguments: any(named: 'arguments'),
              timeout: any(named: 'timeout'),
            ),
          );
        }
      },
    );

    test('falha quando pg_dump está ausente (3ª na ordem)', () async {
      mockTool('psql', ok());
      mockTool('pg_basebackup', ok());
      mockTool('pg_dump', missing());

      final result = await service.verifyPostgresTools();
      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ValidationFailure;
      expect(failure.message, contains('pg_dump'));

      // pg_receivewal não é tocado depois de pg_dump falhar.
      verifyNever(
        () => processService.run(
          executable: 'pg_receivewal',
          arguments: any(named: 'arguments'),
          timeout: any(named: 'timeout'),
        ),
      );
    });
  });
}
