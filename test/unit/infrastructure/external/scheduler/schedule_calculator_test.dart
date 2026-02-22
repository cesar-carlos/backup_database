import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/external/scheduler/cron_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calculator = ScheduleCalculator();

  Schedule buildSchedule({
    bool enabled = true,
    DateTime? nextRunAt,
  }) {
    return Schedule(
      id: 'schedule-1',
      name: 'Backup Diario',
      databaseConfigId: 'db-1',
      databaseType: DatabaseType.sqlServer,
      scheduleType: ScheduleType.daily.name,
      scheduleConfig: '{"hour": 0, "minute": 0}',
      destinationIds: const ['dest-1'],
      backupFolder: r'C:\backup',
      enabled: enabled,
      nextRunAt: nextRunAt,
    );
  }

  group('ScheduleCalculator.shouldRunNow', () {
    test('returns true when nextRunAt is in the past (delayed run)', () {
      final now = DateTime(2026, 2, 19, 12);
      final schedule = buildSchedule(
        nextRunAt: now.subtract(const Duration(minutes: 5)),
      );

      final result = calculator.shouldRunNow(schedule, now: now);

      expect(result, isTrue);
    });

    test('returns false when nextRunAt is in the future', () {
      final now = DateTime(2026, 2, 19, 12);
      final schedule = buildSchedule(
        nextRunAt: now.add(const Duration(minutes: 5)),
      );

      final result = calculator.shouldRunNow(schedule, now: now);

      expect(result, isFalse);
    });

    test('returns false when schedule is disabled', () {
      final now = DateTime(2026, 2, 19, 12);
      final schedule = buildSchedule(
        enabled: false,
        nextRunAt: now.subtract(const Duration(minutes: 1)),
      );

      final result = calculator.shouldRunNow(schedule, now: now);

      expect(result, isFalse);
    });
  });
}
