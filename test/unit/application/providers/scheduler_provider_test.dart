import 'package:backup_database/application/providers/scheduler_provider.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/schedule.dart';
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
    repository = _MockScheduleRepository();
    provider = SchedulerProvider(
      repository: repository,
      schedulerService: _MockSchedulerService(),
      createSchedule: _MockCreateSchedule(),
      updateSchedule: _MockUpdateSchedule(),
      deleteSchedule: _MockDeleteSchedule(),
      executeBackup: _MockExecuteScheduledBackup(),
    );
  });

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
