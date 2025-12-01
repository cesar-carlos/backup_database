import '../../entities/schedule.dart';
import '../../../infrastructure/external/scheduler/cron_parser.dart';

class GetNextRunTime {
  final ScheduleCalculator _calculator = ScheduleCalculator();

  DateTime? call(Schedule schedule) {
    return _calculator.getNextRunTime(schedule);
  }
}

