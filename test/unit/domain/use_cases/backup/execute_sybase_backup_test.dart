import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/use_cases/backup/execute_sybase_backup.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockSybaseBackupService extends Mock implements ISybaseBackupService {}

void main() {
  late _MockSybaseBackupService backupService;
  late ExecuteSybaseBackup useCase;
  late SybaseConfig config;

  setUpAll(() {
    registerFallbackValue(
      SybaseConfig(
        name: 'fallback',
        serverName: 'fallback',
        databaseName: DatabaseName('fallback'),
        username: 'u',
        password: 'p',
      ),
    );
    registerFallbackValue(
      const BackupExecutionContext(
        outputDirectory: '/tmp',
        scheduleId: 's',
      ),
    );
  });

  setUp(() {
    backupService = _MockSybaseBackupService();
    useCase = ExecuteSybaseBackup(backupService);
    config = SybaseConfig(
      id: 'cfg-1',
      name: 'Test',
      serverName: 'Srv',
      databaseName: DatabaseName('db'),
      username: 'dba',
      password: 'secret',
      port: PortNumber(2638),
    );
  });

  group('ExecuteSybaseBackup', () {
    // A.3: antes desta correção, o use case mapeava silenciosamente
    // `differential -> log` no service (sem passar pelo
    // SybaseRejectDifferentialRule). Agora o use case rejeita upfront,
    // espelhando a regra do pipeline.
    test(
      'rejeita backupType=differential com ValidationFailure (achado A.3)',
      () async {
        final result = await useCase(
          config: config,
          outputDirectory: '/tmp/out',
          backupType: BackupType.differential,
        );
        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<ValidationFailure>());
        verifyNever(
          () => backupService.executeBackup(
            config: any(named: 'config'),
            context: any(named: 'context'),
          ),
        );
      },
    );

    test('rejeita tipos convertidos do Sybase ASE (achado A.3)', () async {
      for (final type in const [
        BackupType.convertedDifferential,
        BackupType.convertedFullSingle,
        BackupType.convertedLog,
      ]) {
        final result = await useCase(
          config: config,
          outputDirectory: '/tmp/out',
          backupType: type,
        );
        expect(result.isError(), isTrue, reason: 'rejeita $type');
        expect(
          result.exceptionOrNull(),
          isA<ValidationFailure>(),
          reason: 'rejeita $type',
        );
      }
    });

    // Achado A.2: API ampliada para receber sybaseBackupOptions,
    // backupTimeout, verifyTimeout, cancelTag e scheduleId.
    test(
      'forwarda sybaseBackupOptions/timeouts/scheduleId/cancelTag no '
      'BackupExecutionContext (achado A.2)',
      () async {
        BackupExecutionContext? captured;
        when(
          () => backupService.executeBackup(
            config: any(named: 'config'),
            context: any(named: 'context'),
          ),
        ).thenAnswer((invocation) async {
          captured =
              invocation.namedArguments[#context]! as BackupExecutionContext;
          return const rd.Success(
            BackupExecutionResult(
              backupPath: '/tmp/out/x',
              fileSize: 1,
              duration: Duration.zero,
              databaseName: 'db',
            ),
          );
        });

        const options = SybaseBackupOptions(serverSide: true);
        await useCase(
          config: config,
          outputDirectory: '/tmp/out',
          scheduleId: 'sch-42',
          sybaseBackupOptions: options,
          backupTimeout: const Duration(minutes: 7),
          verifyTimeout: const Duration(minutes: 3),
          cancelTag: 'cancel-99',
        );

        expect(captured, isNotNull);
        expect(captured!.scheduleId, 'sch-42');
        expect(captured!.sybaseBackupOptions, same(options));
        expect(captured!.backupTimeout, const Duration(minutes: 7));
        expect(captured!.verifyTimeout, const Duration(minutes: 3));
        expect(captured!.cancelTag, 'cancel-99');
      },
    );

    test(
      'scheduleId default cai em config.id quando nao informado',
      () async {
        BackupExecutionContext? captured;
        when(
          () => backupService.executeBackup(
            config: any(named: 'config'),
            context: any(named: 'context'),
          ),
        ).thenAnswer((invocation) async {
          captured =
              invocation.namedArguments[#context]! as BackupExecutionContext;
          return const rd.Success(
            BackupExecutionResult(
              backupPath: '/tmp/out/x',
              fileSize: 1,
              duration: Duration.zero,
              databaseName: 'db',
            ),
          );
        });

        await useCase(config: config, outputDirectory: '/tmp/out');
        expect(captured?.scheduleId, config.id);
      },
    );

    test(
      'rejeita campos obrigatorios em branco com ValidationFailure',
      () async {
        final blankServerConfig = SybaseConfig(
          id: 'cfg-2',
          name: 'Test',
          serverName: '',
          databaseName: DatabaseName('db'),
          username: 'dba',
          password: 'p',
        );
        final result = await useCase(
          config: blankServerConfig,
          outputDirectory: '/tmp/out',
        );
        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<ValidationFailure>());
      },
    );
  });
}
