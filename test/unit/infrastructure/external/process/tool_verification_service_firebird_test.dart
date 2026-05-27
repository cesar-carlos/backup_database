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

  ProcessResult okWithTagline(String tagline) => ProcessResult(
    exitCode: 0,
    stdout: '$tagline Firebird 3.0',
    stderr: '',
    duration: const Duration(milliseconds: 8),
  );

  group('verifyFirebirdCliTools', () {
    test(
      'sucesso: cada CLI retorna exit 0 + tagline `WI-V*` (todas as 4 sao '
      'reconhecidas como Firebird real)',
      () async {
        for (final tool in const ['gbak', 'nbackup', 'gstat', 'isql']) {
          when(
            () => processService.run(
              executable: tool,
              arguments: any(named: 'arguments'),
              timeout: any(named: 'timeout'),
            ),
          ).thenAnswer(
            (_) async => rd.Success(okWithTagline('WI-V3.0.10.33601')),
          );
        }

        final result = await service.verifyFirebirdCliTools();
        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), isTrue);

        for (final tool in const ['gbak', 'nbackup', 'gstat', 'isql']) {
          verify(
            () => processService.run(
              executable: tool,
              arguments: any(
                named: 'arguments',
                that: equals(const ['-z']),
              ),
              timeout: any(named: 'timeout'),
            ),
          ).called(1);
        }
      },
    );

    test(
      'rejeita CLI homonima (sem tagline WI-V) — ex.: isql do unixODBC '
      'devolve exit 0 + texto generico, mas nao e o Firebird isql',
      () async {
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => rd.Success(okWithTagline('WI-V3.0.10.33601')),
        );
        when(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => rd.Success(okWithTagline('WI-V3.0.10.33601')),
        );
        when(
          () => processService.run(
            executable: 'gstat',
            arguments: any(named: 'arguments'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => rd.Success(okWithTagline('WI-V3.0.10.33601')),
        );
        // isql impostor: exit 0 mas sem WI-V (output unixODBC, etc.)
        when(
          () => processService.run(
            executable: 'isql',
            arguments: any(named: 'arguments'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'unixODBC interactive SQL\nDSN: ...',
              stderr: '',
              duration: Duration(milliseconds: 4),
            ),
          ),
        );

        final result = await service.verifyFirebirdCliTools();
        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<ValidationFailure>());
      },
    );

    test(
      'rejeita CLI ausente (exit nao-zero) — ex.: gstat fora do PATH',
      () async {
        when(
          () => processService.run(
            executable: 'gbak',
            arguments: any(named: 'arguments'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => rd.Success(okWithTagline('WI-V3.0.10.33601')),
        );
        when(
          () => processService.run(
            executable: 'nbackup',
            arguments: any(named: 'arguments'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => rd.Success(okWithTagline('WI-V3.0.10.33601')),
        );
        when(
          () => processService.run(
            executable: 'gstat',
            arguments: any(named: 'arguments'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'command not found',
              duration: Duration(milliseconds: 2),
            ),
          ),
        );

        final result = await service.verifyFirebirdCliTools();
        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<ValidationFailure>());
        // Nao chega a verificar `isql` (falhamos cedo em gstat)
        verifyNever(
          () => processService.run(
            executable: 'isql',
            arguments: any(named: 'arguments'),
            timeout: any(named: 'timeout'),
          ),
        );
      },
    );

    test(
      'aceita tagline WI-V em stderr (algumas builds escrevem para stderr)',
      () async {
        for (final tool in const ['gbak', 'nbackup', 'gstat', 'isql']) {
          when(
            () => processService.run(
              executable: tool,
              arguments: any(named: 'arguments'),
              timeout: any(named: 'timeout'),
            ),
          ).thenAnswer(
            (_) async => const rd.Success(
              ProcessResult(
                exitCode: 0,
                stdout: '',
                stderr: 'WI-V4.0.2.2867',
                duration: Duration(milliseconds: 6),
              ),
            ),
          );
        }
        final result = await service.verifyFirebirdCliTools();
        expect(result.isSuccess(), isTrue);
      },
    );
  });
}
