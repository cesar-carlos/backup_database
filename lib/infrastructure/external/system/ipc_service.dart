import 'dart:async';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/windows_user_service.dart';
import 'package:backup_database/domain/services/i_ipc_service.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_channel.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_schedule_delegator.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_transport_factory.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_v1_codec.dart';

class IpcService implements IIpcService {
  IpcService({IIpcTransport? transport})
    : _transport = transport ?? IpcTransportFactory.create();

  final IIpcTransport _transport;
  Future<void> Function()? _onShowWindow;
  RunScheduleIpcHandler? _onRunSchedule;
  String _role = SingleInstanceConfig.ipcInstanceRoleUi;
  late final IpcScheduleDelegator _scheduleDelegator = IpcScheduleDelegator(
    handler: () => _onRunSchedule,
    role: () => _role,
  );

  @override
  Future<bool> startServer({
    required String role,
    Future<void> Function()? onShowWindow,
    RunScheduleIpcHandler? onRunSchedule,
  }) async {
    if (_transport.isServerRunning) {
      LoggerService.debug('IPC Server ja esta rodando');
      return true;
    }

    _role = IpcV1Codec.normalizeRole(role);
    _onShowWindow = onShowWindow;
    _onRunSchedule = onRunSchedule;

    final started = await _transport.startServer(
      onConnection: _handleConnection,
    );
    if (!started) {
      LoggerService.error(
        'Nao foi possivel iniciar IPC Server (named pipe)',
      );
      return false;
    }

    LoggerService.infoWithContext(
      'event=ipc_server_started '
      'protocol=${SingleInstanceConfig.ipcProtocolId} ownerRole=$_role '
      'canRunSchedule=$_canRunSchedule',
    );
    return true;
  }

  Future<void> _handleConnection(IIpcChannel channel) async {
    LoggerService.debug('ipc_connection_open');
    try {
      final message = await channel.readLine(
        timeout: SingleInstanceConfig.ipcConnectTimeout,
      );
      if (message == null || message.isEmpty) {
        return;
      }
      LoggerService.debug('ipc_rx len=${message.length}');
      final response = await _dispatch(message);
      if (response != null) {
        await channel.writeLine(response);
      }
    } on Object catch (e) {
      LoggerService.error('Erro ao processar mensagem IPC', e);
    } finally {
      await channel.close();
    }
  }

  Future<String?> _dispatch(String message) async {
    if (message == SingleInstanceConfig.ipcShowWindowMessage) {
      LoggerService.infoWithContext(
        'event=ipc_show_window_received ownerRole=$_role',
      );
      try {
        await _onShowWindow?.call();
        return SingleInstanceConfig.ipcOkAckMessage;
      } on Object catch (e, s) {
        LoggerService.error('Erro no callback SHOW_WINDOW', e, s);
        return null;
      }
    }

    if (message.startsWith(
      '${SingleInstanceConfig.ipcProtocolId}|'
      '${SingleInstanceConfig.ipcRunScheduleCommand}|',
    )) {
      LoggerService.infoWithContext(
        'event=ipc_run_schedule_received ownerRole=$_role '
        'canRunSchedule=$_canRunSchedule',
      );
      final scheduleId = IpcV1Codec.parseRunScheduleRequest(message);
      final result = scheduleId == null
          ? const SingleInstanceScheduledDelegationResult(
              exitCode: 2,
              message:
                  SingleInstanceConfig.ipcRunScheduleMessageInvalidScheduleId,
            )
          : await _scheduleDelegator.runDelegated(scheduleId);
      return IpcV1Codec.buildRunScheduleResultLine(
        exitCode: result.exitCode,
        message: result.message,
      );
    }

    if (message == SingleInstanceConfig.ipcGetUserInfoMessage) {
      LoggerService.debug('ipc_cmd GET_USER_INFO');
      final username =
          WindowsUserService.getCurrentUsername() ?? 'Desconhecido';
      return IpcV1Codec.buildV1UserInfoLine(
        username: username,
        role: _role,
      );
    }

    if (message == SingleInstanceConfig.ipcPingMessage) {
      LoggerService.debug('ipc_ping_v1');
      return IpcV1Codec.buildV1PongLine(
        role: _role,
        canRunSchedule: _canRunSchedule,
      );
    }

    return null;
  }

  Future<IIpcChannel?> _connect({required Duration timeout}) {
    return _transport.connect(timeout: timeout);
  }

  @override
  Future<bool> notifyExistingInstance() async {
    final channel = await _connect(
      timeout: SingleInstanceConfig.showWindowConnectTimeout,
    );
    if (channel == null) {
      LoggerService.warning('ipc_show_window_failed connect');
      return false;
    }
    try {
      await channel.writeLine(SingleInstanceConfig.ipcShowWindowMessage);
      final ack = await channel.readLine(
        timeout: SingleInstanceConfig.showWindowConnectTimeout,
      );
      final ok = IpcV1Codec.isOkAck(ack);
      if (ok) {
        LoggerService.info('ipc_show_window_sent');
      } else {
        LoggerService.debug('ipc_show_window_no_ack');
      }
      return ok;
    } on Object catch (_) {
      return false;
    } finally {
      await channel.close();
    }
  }

  @override
  Future<bool> checkServerRunning() async {
    final info = await getExistingInstanceInfo();
    return info != null;
  }

  @override
  Future<String?> getExistingInstanceUser() async {
    final channel = await _connect(
      timeout: SingleInstanceConfig.ipcConnectTimeout,
    );
    if (channel == null) {
      LoggerService.debug('ipc_user_unresolved');
      return null;
    }
    try {
      await channel.writeLine(SingleInstanceConfig.ipcGetUserInfoMessage);
      final message = await channel.readLine(
        timeout: SingleInstanceConfig.ipcConnectTimeout,
      );
      if (message == null) {
        return null;
      }
      return IpcV1Codec.parseUserInfoResponse(message);
    } on Object catch (_) {
      return null;
    } finally {
      await channel.close();
    }
  }

  @override
  Future<String?> getExistingInstanceRole() async {
    final ownerInfo = await getExistingInstanceInfo();
    return ownerInfo?.role;
  }

  @override
  Future<SingleInstanceOwnerInfo?> getExistingInstanceInfo() async {
    final channel = await _connect(
      timeout: SingleInstanceConfig.ipcConnectTimeout,
    );
    if (channel == null) {
      LoggerService.debug('ipc_owner_info_unresolved');
      return null;
    }
    try {
      await channel.writeLine(SingleInstanceConfig.ipcPingMessage);
      final response = await channel.readLine(
        timeout: SingleInstanceConfig.ipcConnectTimeout,
      );
      if (response == null) {
        return null;
      }
      final ownerInfo = IpcV1Codec.parseOwnerInfoFromV1Pong(response);
      if (ownerInfo != null) {
        LoggerService.infoWithContext(
          'event=ipc_owner_info_resolved ownerRole=${ownerInfo.role} '
          'canRunSchedule=${ownerInfo.canRunSchedule}',
        );
      }
      return ownerInfo;
    } on Object catch (_) {
      return null;
    } finally {
      await channel.close();
    }
  }

  @override
  Future<SingleInstanceScheduledDelegationResult?> delegateScheduledExecution(
    String scheduleId,
  ) async {
    final channel = await _connect(
      timeout: SingleInstanceConfig.ipcConnectTimeout,
    );
    if (channel == null) {
      LoggerService.warning('ipc_run_schedule_failed connect');
      return null;
    }
    try {
      await channel.writeLine(
        SingleInstanceConfig.ipcRunScheduleMessage(scheduleId),
      );
      final response = await channel.readLine(
        timeout: SingleInstanceConfig.scheduledDelegationTimeout,
      );
      if (response == null) {
        LoggerService.warning('event=ipc_run_schedule_timeout');
        return const SingleInstanceScheduledDelegationResult(
          exitCode: 1,
          message: SingleInstanceConfig.ipcRunScheduleMessageDelegationTimeout,
        );
      }
      final result = IpcV1Codec.parseRunScheduleResult(response);
      if (result != null) {
        LoggerService.infoWithContext(
          'event=ipc_run_schedule_result '
          'exitCode=${result.exitCode} message=${result.message ?? ""}',
          scheduleId: scheduleId,
        );
      }
      return result;
    } on TimeoutException {
      LoggerService.warning('event=ipc_run_schedule_timeout');
      return const SingleInstanceScheduledDelegationResult(
        exitCode: 1,
        message: SingleInstanceConfig.ipcRunScheduleMessageDelegationTimeout,
      );
    } on Object catch (e) {
      LoggerService.debug('ipc_run_schedule_miss error=$e');
      return null;
    } finally {
      await channel.close();
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _transport.stopServer();
      LoggerService.info('IPC Server parado');
    } on Object catch (e) {
      LoggerService.error('Erro ao parar IPC Server', e);
    }
  }

  @override
  bool get isRunning => _transport.isServerRunning;

  bool get _canRunSchedule => _onRunSchedule != null;
}
