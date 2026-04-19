import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_backup_schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/use_cases/backup/validate_sybase_log_backup_preflight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockBackupHistoryRepository extends Mock
    implements IBackupHistoryRepository {}

void main() {
  late _MockBackupHistoryRepository repository;
  late ValidateSybaseLogBackupPreflight useCase;

  setUp(() {
    repository = _MockBackupHistoryRepository();
    useCase = ValidateSybaseLogBackupPreflight(repository);
  });

  Schedule sybaseLogSchedule() => SybaseBackupSchedule(
    name: 'Sybase Log',
    databaseConfigId: 'cfg-1',
    databaseType: DatabaseType.sybase,
    scheduleType: 'daily',
    scheduleConfig: '{}',
    destinationIds: const ['dest-1'],
    backupFolder: r'C:\backup',
    backupType: BackupType.log,
    id: 'sched-1',
  );

  group('ValidateSybaseLogBackupPreflight', () {
    test(
      'retorna canProceed=true para databaseType diferente de sybase',
      () async {
        final schedule = Schedule(
          name: 'SQL Server',
          databaseConfigId: 'cfg-1',
          databaseType: DatabaseType.sqlServer,
          scheduleType: 'daily',
          scheduleConfig: '{}',
          destinationIds: const ['dest-1'],
          backupFolder: r'C:\backup',
          backupType: BackupType.log,
          id: 'sched-1',
        );

        final result = await useCase(schedule);

        expect(result.isSuccess(), isTrue);
        result.fold(
          (r) => expect(r.canProceed, isTrue),
          (_) => fail('Expected success'),
        );
        verifyNever(() => repository.getBySchedule(any()));
      },
    );

    test('retorna canProceed=true para backupType full (nao log)', () async {
      final schedule = sybaseLogSchedule().copyWith(
        backupType: BackupType.full,
      );

      final result = await useCase(schedule);

      expect(result.isSuccess(), isTrue);
      result.fold(
        (r) => expect(r.canProceed, isTrue),
        (_) => fail('Expected success'),
      );
      verifyNever(() => repository.getBySchedule(any()));
    });

    test('retorna canProceed=false quando nao existe backup full', () async {
      when(() => repository.getBySchedule(any())).thenAnswer(
        (_) async => const rd.Success(<BackupHistory>[]),
      );

      final result = await useCase(sybaseLogSchedule());

      expect(result.isSuccess(), isTrue);
      result.fold(
        (r) {
          expect(r.canProceed, isFalse);
          expect(r.error, contains('Nenhum backup full encontrado'));
        },
        (_) => fail('Expected success'),
      );
      verify(() => repository.getBySchedule('sched-1')).called(1);
    });

    test('retorna canProceed=true quando existe full bem-sucedido', () async {
      final fullHistory = BackupHistory(
        databaseName: 'testdb',
        databaseType: 'sybase',
        backupPath: r'C:\backup\testdb',
        fileSize: 1000,
        backupType: BackupType.full.name,
        status: BackupStatus.success,
        startedAt: DateTime.now().subtract(const Duration(days: 1)),
        scheduleId: 'sched-1',
        finishedAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      when(() => repository.getBySchedule(any())).thenAnswer(
        (_) async => rd.Success([fullHistory]),
      );

      final result = await useCase(sybaseLogSchedule());

      expect(result.isSuccess(), isTrue);
      result.fold(
        (r) {
          expect(r.canProceed, isTrue);
          expect(r.warning, isNull);
        },
        (_) => fail('Expected success'),
      );
    });

    test('retorna warning quando ultimo full expirado', () async {
      final fullHistory = BackupHistory(
        databaseName: 'testdb',
        databaseType: 'sybase',
        backupPath: r'C:\backup\testdb',
        fileSize: 1000,
        backupType: BackupType.full.name,
        status: BackupStatus.success,
        startedAt: DateTime.now().subtract(const Duration(days: 10)),
        scheduleId: 'sched-1',
        finishedAt: DateTime.now().subtract(const Duration(days: 10)),
      );
      when(() => repository.getBySchedule(any())).thenAnswer(
        (_) async => rd.Success([fullHistory]),
      );

      final result = await useCase(sybaseLogSchedule());

      expect(result.isSuccess(), isTrue);
      result.fold(
        (r) {
          expect(r.canProceed, isTrue);
          expect(r.warning, contains('expirado'));
        },
        (_) => fail('Expected success'),
      );
    });

    test(
      'calcula nextLogSequence corretamente contando logs após o último full',
      () async {
        // Sequência: full (3 dias atrás) + 2 logs após o full + 1 log
        // anterior ao full (não conta).
        final now = DateTime.now();
        final fullHistory = BackupHistory(
          databaseName: 'testdb',
          databaseType: 'sybase',
          backupPath: r'C:\backup\testdb-full',
          fileSize: 1000,
          backupType: BackupType.full.name,
          status: BackupStatus.success,
          startedAt: now.subtract(const Duration(days: 3)),
          scheduleId: 'sched-1',
          finishedAt: now.subtract(const Duration(days: 3)),
        );
        final logBeforeFull = BackupHistory(
          databaseName: 'testdb',
          databaseType: 'sybase',
          backupPath: r'C:\backup\testdb-log0',
          fileSize: 100,
          backupType: BackupType.log.name,
          status: BackupStatus.success,
          // Anterior ao full → NÃO deve contar para nextLogSequence
          startedAt: now.subtract(const Duration(days: 5)),
          scheduleId: 'sched-1',
          finishedAt: now.subtract(const Duration(days: 5)),
        );
        final log1 = BackupHistory(
          databaseName: 'testdb',
          databaseType: 'sybase',
          backupPath: r'C:\backup\testdb-log1',
          fileSize: 100,
          backupType: BackupType.log.name,
          status: BackupStatus.success,
          startedAt: now.subtract(const Duration(days: 2)),
          scheduleId: 'sched-1',
          finishedAt: now.subtract(const Duration(days: 2)),
        );
        final log2 = BackupHistory(
          databaseName: 'testdb',
          databaseType: 'sybase',
          backupPath: r'C:\backup\testdb-log2',
          fileSize: 100,
          backupType: BackupType.log.name,
          status: BackupStatus.success,
          startedAt: now.subtract(const Duration(days: 1)),
          scheduleId: 'sched-1',
          finishedAt: now.subtract(const Duration(days: 1)),
        );
        when(() => repository.getBySchedule(any())).thenAnswer(
          (_) async => rd.Success([logBeforeFull, fullHistory, log1, log2]),
        );

        final result = await useCase(sybaseLogSchedule());

        result.fold(
          (r) {
            expect(r.canProceed, isTrue);
            expect(
              r.nextLogSequence,
              equals(3),
              reason: 'logBeforeFull não conta; 2 logs após full + 1 = 3',
            );
            expect(r.baseFull?.id, equals(fullHistory.id));
          },
          (_) => fail('Expected success'),
        );
      },
    );

    test(
      'emite warning de cadeia quebrada quando último backup terminal foi error',
      () async {
        final now = DateTime.now();
        final fullHistory = BackupHistory(
          databaseName: 'testdb',
          databaseType: 'sybase',
          backupPath: r'C:\backup\testdb-full',
          fileSize: 1000,
          backupType: BackupType.full.name,
          status: BackupStatus.success,
          startedAt: now.subtract(const Duration(days: 2)),
          scheduleId: 'sched-1',
          finishedAt: now.subtract(const Duration(days: 2)),
        );
        final lastErrorBackup = BackupHistory(
          databaseName: 'testdb',
          databaseType: 'sybase',
          backupPath: r'C:\backup\testdb-log-failed',
          fileSize: 0,
          backupType: BackupType.log.name,
          status: BackupStatus.error,
          startedAt: now.subtract(const Duration(hours: 1)),
          scheduleId: 'sched-1',
          finishedAt: now.subtract(const Duration(hours: 1)),
        );
        when(() => repository.getBySchedule(any())).thenAnswer(
          (_) async => rd.Success([fullHistory, lastErrorBackup]),
        );

        final result = await useCase(sybaseLogSchedule());

        result.fold(
          (r) {
            expect(r.canProceed, isTrue);
            expect(r.warning, contains('cadeia de logs pode estar comprometida'));
          },
          (_) => fail('Expected success'),
        );
      },
    );

    test(
      'ignora histórico em status running ao detectar último backup terminal '
      '(evita falso warning de cadeia quebrada)',
      () async {
        // Bug histórico: usar `histories.reduce(max-by date)` sem filtrar
        // running pegava um job zumbi como "último", e como running não
        // tinha `finishedAt`, o `.startedAt` proxy disparava warning de
        // cadeia quebrada falsamente.
        final now = DateTime.now();
        final fullHistory = BackupHistory(
          databaseName: 'testdb',
          databaseType: 'sybase',
          backupPath: r'C:\backup\testdb-full',
          fileSize: 1000,
          backupType: BackupType.full.name,
          status: BackupStatus.success,
          startedAt: now.subtract(const Duration(days: 2)),
          scheduleId: 'sched-1',
          finishedAt: now.subtract(const Duration(days: 2)),
        );
        final runningZombie = BackupHistory(
          databaseName: 'testdb',
          databaseType: 'sybase',
          backupPath: '',
          fileSize: 0,
          backupType: BackupType.log.name,
          // Status `running` — provavelmente zumbi não-reconciliado
          status: BackupStatus.running,
          startedAt: now.subtract(const Duration(hours: 6)),
          scheduleId: 'sched-1',
          // Sem finishedAt — confirmaria comportamento inconsistente
          // se o método não filtrasse running.
        );
        when(() => repository.getBySchedule(any())).thenAnswer(
          (_) async => rd.Success([fullHistory, runningZombie]),
        );

        final result = await useCase(sybaseLogSchedule());

        result.fold(
          (r) {
            expect(r.canProceed, isTrue);
            expect(
              r.warning,
              isNull,
              reason:
                  'running zombie should NOT trigger chain-broken warning; '
                  'last terminal is the full backup, which was successful',
            );
          },
          (_) => fail('Expected success'),
        );
      },
    );
  });
}
