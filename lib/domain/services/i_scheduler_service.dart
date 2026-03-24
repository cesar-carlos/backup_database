import 'package:result_dart/result_dart.dart';

abstract class ISchedulerService {
  /// True while [executeNow] is actively running a backup (lock held).
  bool get isExecutingBackup;

  Future<Result<void>> executeNow(String scheduleId);

  Future<Result<void>> cancelExecution(String scheduleId);

  Future<Result<void>> refreshSchedule(String scheduleId);

  Future<void> start();

  void stop();

  bool get isRunning;

  Future<bool> waitForRunningBackups({
    Duration timeout = const Duration(minutes: 5),
  });
}
