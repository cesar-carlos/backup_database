import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';

class IpcScheduleDelegator {
  IpcScheduleDelegator({
    required this._handler,
    required this._role,
  });

  final RunScheduleIpcHandler? Function() _handler;
  final String Function() _role;

  Future<SingleInstanceScheduledDelegationResult> runDelegated(
    String scheduleId,
  ) async {
    final handler = _handler();
    if (handler == null) {
      LoggerService.warning(
        'event=ipc_run_schedule_no_handler ownerRole=${_role()}',
      );
      return const SingleInstanceScheduledDelegationResult(
        exitCode: 1,
        message:
            SingleInstanceConfig.ipcRunScheduleMessageOwnerCannotRunSchedule,
      );
    }

    try {
      final exitCode = await handler(scheduleId);
      return SingleInstanceScheduledDelegationResult(
        exitCode: exitCode,
        message: exitCode == 0
            ? SingleInstanceConfig.ipcRunScheduleMessageOk
            : SingleInstanceConfig.ipcRunScheduleMessageExecutionFailed,
      );
    } on Object catch (e, s) {
      LoggerService.error('ipc_run_schedule_handler_failed', e, s);
      return const SingleInstanceScheduledDelegationResult(
        exitCode: 1,
        message: SingleInstanceConfig.ipcRunScheduleMessageExecutionFailed,
      );
    }
  }
}
