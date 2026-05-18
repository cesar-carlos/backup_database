import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/firebird_backup_strategy.dart';
import 'package:backup_database/application/services/strategies/rules/firebird_supported_backup_types_rule.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockFb extends Mock implements IFirebirdBackupService {}

void main() {
  late FirebirdConfig fbCfg;
  late Schedule schedule;

  setUpAll(() {
    registerFallbackValue(
      FirebirdConfig(
        name: 'n',
        host: 'h',
        databaseFile: 'f',
        username: 'u',
        password: 'p',
      ),
    );
    registerFallbackValue(
      const BackupExecutionContext(
        outputDirectory: 'o',
        scheduleId: 's',
      ),
    );
  });

  setUp(() {
    fbCfg = FirebirdConfig(
      name: 'fb',
      host: 'localhost',
      databaseFile: r'C:\d.fdb',
      username: 'u',
      password: 'p',
    );
    schedule = Schedule(
      name: 'sch',
      databaseConfigId: 'cfg',
      databaseType: DatabaseType.firebird,
      scheduleType: 'daily',
      scheduleConfig: '{}',
      destinationIds: const [],
      backupFolder: 'bf',
    );
  });

  group('FirebirdSupportedBackupTypesRule', () {
    final rule = FirebirdSupportedBackupTypesRule();
    final ctx = BackupPipelineContext();

    test('allows full and fullSingle', () async {
      for (final t in [BackupType.full, BackupType.fullSingle]) {
        final r = await rule.validate(
          ctx,
          schedule: schedule,
          config: fbCfg,
          backupType: t,
        );
        expect(r.isSuccess(), isTrue, reason: '$t');
      }
    });

    test(
      'allows full fullSingle differential log and converted log/diff',
      () async {
        for (final t in [
          BackupType.full,
          BackupType.fullSingle,
          BackupType.differential,
          BackupType.log,
          BackupType.convertedDifferential,
          BackupType.convertedLog,
        ]) {
          final r = await rule.validate(
            ctx,
            schedule: schedule,
            config: fbCfg,
            backupType: t,
          );
          expect(r.isSuccess(), isTrue, reason: '$t');
        }
      },
    );

    test('rejects converted full single only', () async {
      final r = await rule.validate(
        ctx,
        schedule: schedule,
        config: fbCfg,
        backupType: BackupType.convertedFullSingle,
      );
      expect(r.isError(), isTrue);
    });
  });

  group('FirebirdBackupStrategy', () {
    test('getDatabaseSizeBytes forwards to service', () async {
      final mock = _MockFb();
      when(
        () => mock.getDatabaseSizeBytes(
          config: any(named: 'config'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => const rd.Success(99));

      final strategy = FirebirdBackupStrategy(mock);
      final r = await strategy.getDatabaseSizeBytes(
        databaseConfig: fbCfg,
        timeout: const Duration(seconds: 5),
      );

      expect(r.isSuccess(), isTrue);
      expect(r.getOrNull(), 99);
      verify(
        () => mock.getDatabaseSizeBytes(
          config: fbCfg,
          timeout: const Duration(seconds: 5),
        ),
      ).called(1);
    });

    test('execute with full invokes executeBackup', () async {
      final mock = _MockFb();
      when(
        () => mock.executeBackup(
          config: any(named: 'config'),
          context: any(named: 'context'),
        ),
      ).thenAnswer(
        (_) async => const rd.Success(
          BackupExecutionResult(
            backupPath: '/b.fbk',
            fileSize: 10,
            duration: Duration.zero,
            databaseName: 'd',
          ),
        ),
      );

      final strategy = FirebirdBackupStrategy(mock);
      final r = await strategy.execute(
        schedule: schedule,
        databaseConfig: fbCfg,
        outputDirectory: '/tmp',
        backupType: BackupType.full,
        cancelTag: 'ct',
      );

      expect(r.isSuccess(), isTrue);
      expect(r.getOrNull()?.backupPath, '/b.fbk');
      verify(
        () => mock.executeBackup(
          config: fbCfg,
          context: any(named: 'context'),
        ),
      ).called(1);
    });

    test(
      'execute forwards schedule firebirdNbackupPhysicalLevel in context',
      () async {
        final mock = _MockFb();
        final sched = schedule.copyWith(firebirdNbackupPhysicalLevel: 4);
        when(
          () => mock.executeBackup(
            config: any(named: 'config'),
            context: any(named: 'context'),
          ),
        ).thenAnswer((invocation) async {
          final BackupExecutionContext ctx =
              invocation.namedArguments[#context]! as BackupExecutionContext;
          expect(ctx.firebirdNbackupPhysicalLevel, 4);
          return const rd.Success(
            BackupExecutionResult(
              backupPath: '/x.nbk',
              fileSize: 1,
              duration: Duration.zero,
              databaseName: 'd',
            ),
          );
        });

        final strategy = FirebirdBackupStrategy(mock);
        final r = await strategy.execute(
          schedule: sched,
          databaseConfig: fbCfg,
          outputDirectory: '/tmp',
          backupType: BackupType.differential,
          cancelTag: 'ct',
        );

        expect(r.isSuccess(), isTrue);
        verify(
          () => mock.executeBackup(
            config: fbCfg,
            context: any(named: 'context'),
          ),
        ).called(1);
      },
    );
  });
}
