import 'dart:async';

import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:backup_database/application/providers/scheduler_provider.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/use_cases/scheduling/create_schedule.dart';
import 'package:backup_database/domain/use_cases/scheduling/delete_schedule.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/domain/use_cases/scheduling/update_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

class _MockSchedulerService extends Mock implements ISchedulerService {}

class _MockCreateSchedule extends Mock implements CreateSchedule {}

class _MockUpdateSchedule extends Mock implements UpdateSchedule {}

class _MockDeleteSchedule extends Mock implements DeleteSchedule {}

class _MockExecuteScheduledBackup extends Mock
    implements ExecuteScheduledBackup {}

void main() {
  late _MockScheduleRepository repository;
  late SchedulerProvider provider;
  late _MockCreateSchedule createSchedule;
  late _MockExecuteScheduledBackup executeBackup;
  late BackupProgressProvider progress;

  const configId = 'config-1';
  final schedule = Schedule(
    id: 'schedule-1',
    name: 'Backup Diario',
    databaseConfigId: configId,
    databaseType: DatabaseType.sqlServer,
    scheduleType: ScheduleType.daily.name,
    scheduleConfig: '{"hour": 0, "minute": 0}',
    destinationIds: const ['dest-1'],
    backupFolder: r'C:\backup',
  );

  setUp(() {
    registerFallbackValue(schedule);
    repository = _MockScheduleRepository();
    createSchedule = _MockCreateSchedule();
    executeBackup = _MockExecuteScheduledBackup();
    progress = BackupProgressProvider();
    provider = SchedulerProvider(
      repository: repository,
      schedulerService: _MockSchedulerService(),
      createSchedule: createSchedule,
      updateSchedule: _MockUpdateSchedule(),
      deleteSchedule: _MockDeleteSchedule(),
      executeBackup: executeBackup,
      progressProvider: progress,
    );
  });

  tearDown(() {
    provider.dispose();
    progress.dispose();
  });

  test(
    'duplicate preserves engine options and policies but resets history',
    () async {
      final original = schedule.copyWith(
        verifyPolicy: VerifyPolicy.strict,
        backupTimeout: const Duration(hours: 5),
        verifyTimeout: const Duration(minutes: 12),
        firebirdNbackupPhysicalLevel: 2,
        isConvertedDifferential: true,
        sqlServerBackupOptions: const SqlServerBackupOptions(
          compression: true,
          stripingCount: 2,
        ),
        sybaseBackupOptions: const SybaseBackupOptions(serverSide: true),
        lastRunAt: DateTime(2026),
        nextRunAt: DateTime(2027),
        createdAt: DateTime(2025),
        updatedAt: DateTime(2026),
      );
      when(() => createSchedule(any())).thenAnswer(
        (invocation) async =>
            rd.Success(invocation.positionalArguments.first as Schedule),
      );
      when(() => repository.getAll())
          .thenAnswer((_) async => const rd.Success(<Schedule>[]));
      expect(await provider.duplicateSchedule(original), isTrue);
      final copy =
          verify(() => createSchedule(captureAny())).captured.single
              as Schedule;
      expect(copy.id, isNot(original.id));
      expect(copy.name, '${original.name} (cópia)');
      expect(copy.verifyPolicy, VerifyPolicy.strict);
      expect(copy.backupTimeout, original.backupTimeout);
      expect(copy.verifyTimeout, original.verifyTimeout);
      expect(copy.firebirdNbackupPhysicalLevel, 2);
      expect(copy.isConvertedDifferential, isTrue);
      expect(copy.sqlServerBackupOptions, original.sqlServerBackupOptions);
      expect(copy.sybaseBackupOptions, original.sybaseBackupOptions);
      expect(copy.destinationIds, original.destinationIds);
      expect(copy.lastRunAt, isNull);
      expect(copy.nextRunAt, isNull);
      expect(copy.createdAt, isNull);
      expect(copy.updatedAt, isNull);
    },
  );

  for (final fail in [false, true]) {
    test(
      'late execution result cannot overwrite another backup (failure: $fail)',
      () async {
        final pending = Completer<rd.Result<void>>();
        when(() => executeBackup(schedule.id))
            .thenAnswer((_) => pending.future);
        final work = provider.executeNow(schedule.id);
        progress.completeBackup();
        progress.startBackup('New backup');
        progress.updateProgress(
          step: 'Compactando',
          message: 'New progress',
          progress: 0.6,
        );
        pending.complete(
          fail
              ? const rd.Failure(BackupFailure(message: 'Old failure'))
              : const rd.Success(rd.unit),
        );
        expect(await work, !fail);
        expect(progress.isRunning, isTrue);
        expect(progress.currentBackupName, 'New backup');
        expect(progress.currentProgress!.message, 'New progress');
        expect(progress.currentProgress!.progress, 0.6);
      },
    );
  }

  test(
    'executor cancellation details survive provider failure handling',
    () async {
      when(() => executeBackup(schedule.id)).thenAnswer((_) async {
        progress.cancelBackup('operator');
        return const rd.Failure(BackupFailure(message: 'cancelled'));
      });
      expect(await provider.executeNow(schedule.id), isFalse);
      expect(progress.currentProgress!.cancelled, isTrue);
      expect(progress.currentProgress!.message, 'Backup cancelado');
      expect(progress.currentProgress!.error, 'operator');
    },
  );

  group('SchedulerProvider.getSchedulesByDatabaseConfig', () {
    test('returns schedules when repository succeeds', () async {
      when(
        () => repository.getByDatabaseConfig(configId),
      ).thenAnswer((_) async => rd.Success(<Schedule>[schedule]));

      final result = await provider.getSchedulesByDatabaseConfig(configId);

      expect(result, isNotNull);
      expect(result, hasLength(1));
      expect(result!.first.id, equals(schedule.id));
      verify(() => repository.getByDatabaseConfig(configId)).called(1);
    });

    test('returns null when repository fails', () async {
      when(
        () => repository.getByDatabaseConfig(configId),
      ).thenAnswer(
        (_) async => const rd.Failure(
          DatabaseFailure(message: 'erro ao buscar agendamentos'),
        ),
      );

      final result = await provider.getSchedulesByDatabaseConfig(configId);

      expect(result, isNull);
      verify(() => repository.getByDatabaseConfig(configId)).called(1);
    });
  });
}
