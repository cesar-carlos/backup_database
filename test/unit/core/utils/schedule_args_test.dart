import 'package:backup_database/core/utils/schedule_args.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduleArgs.extract', () {
    test('returns null when no args', () {
      expect(ScheduleArgs.extract(const <String>[]), isNull);
    });

    test('returns null when args have no schedule prefix', () {
      expect(
        ScheduleArgs.extract(const ['--minimized', '--mode=server']),
        isNull,
      );
    });

    test('returns id when args contain schedule prefix', () {
      expect(
        ScheduleArgs.extract(const ['--schedule-id=abc-123', '--minimized']),
        equals('abc-123'),
      );
    });

    test('returns empty string when arg uses prefix without value', () {
      expect(ScheduleArgs.extract(const ['--schedule-id=']), equals(''));
    });
  });

  group('ScheduleArgs.contains', () {
    test('returns false when no schedule prefix', () {
      expect(ScheduleArgs.contains(const ['--minimized']), isFalse);
    });

    test('returns true when prefix is present', () {
      expect(ScheduleArgs.contains(const ['--schedule-id=abc']), isTrue);
    });
  });

  group('scheduleIdArgument', () {
    test('builds canonical CLI form', () {
      expect(
        scheduleIdArgument('11111111-2222-3333-4444-555555555555'),
        equals('--schedule-id=11111111-2222-3333-4444-555555555555'),
      );
    });
  });
}
