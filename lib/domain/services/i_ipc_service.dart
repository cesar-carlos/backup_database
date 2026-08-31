import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';

abstract class IIpcService {
  Future<bool> startServer({
    required String role,
    Future<void> Function()? onShowWindow,
    RunScheduleIpcHandler? onRunSchedule,
  });

  Future<void> stop();

  bool get isRunning;

  Future<bool> notifyExistingInstance();

  Future<bool> checkServerRunning();

  Future<String?> getExistingInstanceUser();

  Future<String?> getExistingInstanceRole();

  Future<SingleInstanceOwnerInfo?> getExistingInstanceInfo();

  Future<SingleInstanceScheduledDelegationResult?> delegateScheduledExecution(
    String scheduleId,
  );
}
