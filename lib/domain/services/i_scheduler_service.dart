import 'package:backup_database/domain/entities/execution_origin.dart';
import 'package:result_dart/result_dart.dart';

abstract class ISchedulerService {
  /// True while [executeNow] is actively running a backup (lock held).
  bool get isExecutingBackup;

  /// [executionOrigin] default [ExecutionOrigin.local] (timer, UI "Run now").
  /// [ExecutionOrigin.remoteCommand] para início vindo do cliente via socket
  /// (ver ADR-001: sem upload para destinos finais no host).
  Future<Result<void>> executeNow(
    String scheduleId, {
    ExecutionOrigin executionOrigin = ExecutionOrigin.local,
  });

  Future<Result<void>> cancelExecution(String scheduleId);

  Future<Result<void>> refreshSchedule(String scheduleId);

  Future<void> start();

  void stop();

  bool get isRunning;

  Future<bool> waitForRunningBackups({
    Duration timeout = const Duration(minutes: 5),
  });
}
