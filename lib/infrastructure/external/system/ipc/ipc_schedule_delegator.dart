import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_port_probe.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_v1_codec.dart';

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

  static Future<SingleInstanceScheduledDelegationResult?>
  delegateToExistingInstance(String scheduleId) async {
    final portsToTry = IpcPortProbe.portsToTry();

    for (final port in portsToTry) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: SingleInstanceConfig.ipcConnectTimeout,
        );

        socket.add(
          utf8.encode(SingleInstanceConfig.ipcRunScheduleMessage(scheduleId)),
        );
        await socket.flush();

        final data = await socket.first.timeout(
          SingleInstanceConfig.scheduledDelegationTimeout,
        );
        final response = utf8.decode(data).trim();
        final result = IpcV1Codec.parseRunScheduleResult(response);
        if (result != null) {
          IpcPortProbe.markActive(port);
          LoggerService.infoWithContext(
            'event=ipc_run_schedule_result port=$port '
            'exitCode=${result.exitCode} message=${result.message ?? ""}',
            scheduleId: scheduleId,
          );
          return result;
        }
      } on TimeoutException {
        LoggerService.warning(
          'event=ipc_run_schedule_timeout port=$port',
        );
        return const SingleInstanceScheduledDelegationResult(
          exitCode: 1,
          message: SingleInstanceConfig.ipcRunScheduleMessageDelegationTimeout,
        );
      } on Object catch (e) {
        LoggerService.debug('ipc_run_schedule_miss port=$port error=$e');
      } finally {
        await IpcPortProbe.closeClientResources(socket: socket);
      }
    }

    LoggerService.warning(
      'ipc_run_schedule_failed ports_tried=${portsToTry.length}',
    );
    return null;
  }
}
