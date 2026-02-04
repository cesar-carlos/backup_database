import 'package:backup_database/domain/entities/schedule.dart';

abstract class IScheduleCalculator {
  DateTime? getNextRunTime(Schedule schedule, {DateTime? from});
  bool shouldRunNow(Schedule schedule, {DateTime? now});
}
