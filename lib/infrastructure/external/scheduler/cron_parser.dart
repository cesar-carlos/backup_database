import 'dart:convert';

import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/schedule_config.dart';
import 'package:backup_database/domain/services/i_schedule_calculator.dart';

class ScheduleCalculator implements IScheduleCalculator {
  @override
  DateTime? getNextRunTime(Schedule schedule, {DateTime? from}) {
    final now = from ?? DateTime.now();

    switch (scheduleTypeFromString(schedule.scheduleType)) {
      case ScheduleType.daily:
        return _getNextDailyRun(schedule.scheduleConfig, now);
      case ScheduleType.weekly:
        return _getNextWeeklyRun(schedule.scheduleConfig, now);
      case ScheduleType.monthly:
        return _getNextMonthlyRun(schedule.scheduleConfig, now);
      case ScheduleType.interval:
        return _getNextIntervalRun(schedule, now);
    }
  }

  DateTime? _getNextDailyRun(String configJson, DateTime now) {
    try {
      final config = DailyScheduleConfig.fromJson(
        _parseJson(configJson),
      );

      var next = DateTime(
        now.year,
        now.month,
        now.day,
        config.hour,
        config.minute,
      );

      if (next.isBefore(now) || next.isAtSameMomentAs(now)) {
        next = next.add(const Duration(days: 1));
      }

      return next;
    } on Object catch (e) {
      return null;
    }
  }

  DateTime? _getNextWeeklyRun(String configJson, DateTime now) {
    try {
      final config = WeeklyScheduleConfig.fromJson(
        _parseJson(configJson),
      );

      if (config.daysOfWeek.isEmpty) return null;

      for (var i = 0; i < 8; i++) {
        final candidate = now.add(Duration(days: i));
        final candidateWeekday = candidate.weekday;

        if (config.daysOfWeek.contains(candidateWeekday)) {
          final next = DateTime(
            candidate.year,
            candidate.month,
            candidate.day,
            config.hour,
            config.minute,
          );

          if (next.isAfter(now)) {
            return next;
          }
        }
      }

      return null;
    } on Object catch (e) {
      return null;
    }
  }

  DateTime? _getNextMonthlyRun(String configJson, DateTime now) {
    try {
      final config = MonthlyScheduleConfig.fromJson(
        _parseJson(configJson),
      );

      if (config.daysOfMonth.isEmpty) return null;

      for (var monthOffset = 0; monthOffset < 13; monthOffset++) {
        final targetMonth = DateTime(now.year, now.month + monthOffset);
        final daysInMonth = DateTime(
          targetMonth.year,
          targetMonth.month + 1,
          0,
        ).day;

        for (final day in config.daysOfMonth) {
          if (day <= daysInMonth) {
            final candidate = DateTime(
              targetMonth.year,
              targetMonth.month,
              day,
              config.hour,
              config.minute,
            );

            if (candidate.isAfter(now)) {
              return candidate;
            }
          }
        }
      }

      return null;
    } on Object catch (e) {
      return null;
    }
  }

  DateTime? _getNextIntervalRun(Schedule schedule, DateTime now) {
    try {
      final config = IntervalScheduleConfig.fromJson(
        _parseJson(schedule.scheduleConfig),
      );

      if (schedule.lastRunAt == null) {
        return now;
      }

      final next = schedule.lastRunAt!.add(
        Duration(minutes: config.intervalMinutes),
      );

      if (next.isBefore(now)) {
        return now;
      }

      return next;
    } on Object catch (e) {
      return null;
    }
  }

  Map<String, dynamic> _parseJson(String json) {
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } on Object catch (e) {
      return {};
    }
  }

  @override
  bool shouldRunNow(Schedule schedule, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();

    if (!schedule.enabled) return false;
    if (schedule.nextRunAt == null) return false;

    final diff = schedule.nextRunAt!.difference(currentTime);
    final diffInSeconds = diff.inSeconds;

    if (diffInSeconds > 0) {
      return false;
    }

    return true;
  }

  static String createDailyConfig({
    required int hour,
    required int minute,
  }) {
    return jsonEncode(
      DailyScheduleConfig(
        hour: hour,
        minute: minute,
      ).toJson(),
    );
  }

  static String createWeeklyConfig({
    required int hour,
    required int minute,
    required List<int> daysOfWeek,
  }) {
    return jsonEncode(
      WeeklyScheduleConfig(
        hour: hour,
        minute: minute,
        daysOfWeek: daysOfWeek,
      ).toJson(),
    );
  }

  static String createMonthlyConfig({
    required int hour,
    required int minute,
    required List<int> daysOfMonth,
  }) {
    return jsonEncode(
      MonthlyScheduleConfig(
        hour: hour,
        minute: minute,
        daysOfMonth: daysOfMonth,
      ).toJson(),
    );
  }

  static String createIntervalConfig({
    required int intervalMinutes,
  }) {
    return jsonEncode(
      IntervalScheduleConfig(
        intervalMinutes: intervalMinutes,
      ).toJson(),
    );
  }
}
