import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/i_schedule_calculator.dart';

class GetNextRunTime {
  GetNextRunTime(this._calculator);
  final IScheduleCalculator _calculator;

  DateTime? call(Schedule schedule) {
    return _calculator.getNextRunTime(schedule);
  }
}
