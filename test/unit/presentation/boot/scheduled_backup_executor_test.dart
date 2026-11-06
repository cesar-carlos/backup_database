import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/presentation/boot/scheduled_backup_executor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart';

class _Scheduler extends Mock implements ISchedulerService {}

void main() {
  const id = '123e4567-e89b-42d3-a456-426614174000';
  late _Scheduler scheduler;
  setUp(() {
    scheduler = _Scheduler();
    getIt.registerSingleton<ISchedulerService>(scheduler);
  });
  tearDown(() async {
    await getIt.reset();
  });

  test('returns failure when scheduler returns a Failure', () async {
    when(() => scheduler.executeNow(id)).thenAnswer(
      (_) async => Failure(Exception('backup failed')),
    );
    expect(
      await ScheduledBackupExecutor.execute(id),
      ScheduledBackupExitCode.genericFailure,
    );
  });
  test('returns success only for a successful result', () async {
    when(() => scheduler.executeNow(id)).thenAnswer(
      (_) async => const Success(unit),
    );
    expect(
      await ScheduledBackupExecutor.execute(id),
      ScheduledBackupExitCode.success,
    );
  });
  test('returns failure when scheduler throws', () async {
    when(() => scheduler.executeNow(id)).thenThrow(StateError('unavailable'));
    expect(
      await ScheduledBackupExecutor.execute(id),
      ScheduledBackupExitCode.genericFailure,
    );
  });
  test('rejects invalid UUID before invoking scheduler', () async {
    expect(
      await ScheduledBackupExecutor.execute('invalid'),
      ScheduledBackupExitCode.invalidScheduleId,
    );
    verifyNever(() => scheduler.executeNow(any()));
  });
}
