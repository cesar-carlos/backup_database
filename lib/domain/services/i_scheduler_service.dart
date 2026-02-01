import 'package:result_dart/result_dart.dart';

abstract class ISchedulerService {
  Future<Result<void>> executeNow(String scheduleId);

  Future<Result<void>> refreshSchedule(String scheduleId);

  void start();

  void stop();

  bool get isRunning;
}
