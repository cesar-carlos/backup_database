import 'package:backup_database/domain/services/i_ipc_service.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';

class SingleInstanceIpcClient implements ISingleInstanceIpcClient {
  SingleInstanceIpcClient({IIpcService? ipc}) : _ipc = ipc ?? IpcService();

  final IIpcService _ipc;

  @override
  Future<bool> notifyExistingInstance() {
    return _ipc.notifyExistingInstance();
  }

  @override
  Future<bool> checkServerRunning() {
    return _ipc.checkServerRunning();
  }

  @override
  Future<String?> getExistingInstanceUser() {
    return _ipc.getExistingInstanceUser();
  }

  @override
  Future<String?> getExistingInstanceRole() {
    return _ipc.getExistingInstanceRole();
  }

  @override
  Future<SingleInstanceOwnerInfo?> getExistingInstanceInfo() {
    return _ipc.getExistingInstanceInfo();
  }

  @override
  Future<SingleInstanceScheduledDelegationResult?> delegateScheduledExecution(
    String scheduleId,
  ) {
    return _ipc.delegateScheduledExecution(scheduleId);
  }
}
