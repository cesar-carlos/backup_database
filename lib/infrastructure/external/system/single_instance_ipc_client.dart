import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';

class SingleInstanceIpcClient implements ISingleInstanceIpcClient {
  @override
  Future<bool> notifyExistingInstance() {
    return IpcService.sendShowWindow();
  }

  @override
  Future<bool> checkServerRunning() {
    return IpcService.checkServerRunning();
  }

  @override
  Future<String?> getExistingInstanceUser() {
    return IpcService.getExistingInstanceUser();
  }

  @override
  Future<String?> getExistingInstanceRole() {
    return IpcService.getExistingInstanceRole();
  }

  @override
  Future<SingleInstanceOwnerInfo?> getExistingInstanceInfo() {
    return IpcService.getExistingInstanceInfo();
  }

  @override
  Future<SingleInstanceScheduledDelegationResult?> delegateScheduledExecution(
    String scheduleId,
  ) {
    return IpcService.delegateScheduledExecution(scheduleId);
  }
}
