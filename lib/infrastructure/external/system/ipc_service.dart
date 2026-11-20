import 'dart:async';
import 'dart:convert';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/errors/service_connection_exception.dart';
import 'package:backup_database/core/utils/ipc_show_window_confirmation.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/windows_user_service.dart';
import 'package:backup_database/domain/services/i_ipc_service.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc/admin_scheduler_endpoint.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_channel.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_schedule_delegator.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_transport_factory.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_v1_codec.dart';

class IpcService implements IIpcService {
  IpcService({IIpcTransport? transport, Duration? writeTimeout})
    : _transport = transport ?? IpcTransportFactory.create(),
      _writeTimeout = writeTimeout ?? SingleInstanceConfig.ipcConnectTimeout;

  final IIpcTransport _transport;
  final Duration _writeTimeout;
  Future<void> _lifecycle = Future<void>.value();

  Future<T> _serializeLifecycle<T>(Future<T> Function() action) {
    final result = _lifecycle.then((_) => action());
    _lifecycle = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _write(IIpcChannel channel, String message) =>
      channel.writeLine(message).timeout(_writeTimeout);

  /// Only the executor installs this handler. Administrative UI pipes expose
  /// window activation only; commands always target the machine-global pipe.
  final _admin = AdminSchedulerEndpoint();
  ISchedulerService? get scheduler => _admin.scheduler;
  set scheduler(ISchedulerService? value) => _admin.scheduler = value;
  Future<Object?> Function()? _onShowWindow;
  RunScheduleIpcHandler? _onRunSchedule;
  String _role = SingleInstanceConfig.ipcInstanceRoleUi;
  late final IpcScheduleDelegator _scheduleDelegator = IpcScheduleDelegator(
    handler: () => _onRunSchedule,
    role: () => _role,
  );

  @override
  Future<bool> startServer({
    required String role,
    Future<Object?> Function()? onShowWindow,
    RunScheduleIpcHandler? onRunSchedule,
  }) => _serializeLifecycle(
    () => _startServer(
      role: role,
      onShowWindow: onShowWindow,
      onRunSchedule: onRunSchedule,
    ),
  );

  Future<bool> _startServer({
    required String role,
    Future<Object?> Function()? onShowWindow,
    RunScheduleIpcHandler? onRunSchedule,
  }) async {
    if (_transport.isServerRunning) {
      LoggerService.debug('IPC Server ja esta rodando');
      return true;
    }

    _admin.newGeneration();
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
        await _write(channel, response);
      }
    } on Object catch (e) {
      LoggerService.error('Erro ao processar mensagem IPC', e);
    } finally {
      await channel.close();
    }
  }

  Future<String?> _dispatch(String message) async {
    if (message.startsWith('BD_ADMIN_V1|')) {
      final parts = message.split('|');
      if (parts.length != 3) {
        return jsonEncode({'ok': false, 'error': 'Comando inválido'});
      }
      return jsonEncode(await _admin.dispatch(parts[1], parts[2]));
    }
    if (message == SingleInstanceConfig.ipcShowWindowMessage) {
      LoggerService.infoWithContext(
        'event=ipc_show_window_received ownerRole=$_role',
      );
      return _replyShowWindow();
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

  Future<Map<String, dynamic>> schedulerRequest(
    String command, [
    String scheduleId = '',
  ]) async {
    final elapsed = Stopwatch()..start();
    final channel = await _connect(
      timeout: SingleInstanceConfig.ipcConnectTimeout,
    );
    if (channel == null) {
      final transport = _transport;
      final reason = transport is IpcConnectionDiagnostics
          ? (transport as IpcConnectionDiagnostics).lastConnectionFailure
          : null;
      LoggerService.warning(
        'event=ipc_scheduler_connect_failed command=$command '
        'elapsedMs=${elapsed.elapsedMilliseconds} reason=${reason ?? 'channel_unavailable'}',
      );
      throw ServiceConnectionException(reason: reason);
    }
    var phase = 'write';
    try {
      await _write(channel, 'BD_ADMIN_V1|$command|$scheduleId');
      phase = 'read';
      final response = await channel.readLine(
        timeout: command == 'execute'
            ? SingleInstanceConfig.scheduledDelegationTimeout
            : SingleInstanceConfig.ipcConnectTimeout,
      );
      if (response == null) {
        throw StateError(
          'Sem resposta do serviço. A operação pode continuar no servidor; consulte os logs antes de tentar novamente.',
        );
      }
      phase = 'decode';
      final reply = jsonDecode(response) as Map<String, dynamic>;
      if (reply['ok'] is! bool) {
        throw const FormatException('Missing IPC result');
      }
      if (reply['ok'] != true) {
        LoggerService.warning(
          'event=ipc_scheduler_rejected command=$command '
          'code=${reply['code']} elapsedMs=${elapsed.elapsedMilliseconds}',
        );
      }
      return reply;
    } on Object catch (e, s) {
      LoggerService.warning(
        'event=ipc_scheduler_request_failed command=$command phase=$phase '
        'elapsedMs=${elapsed.elapsedMilliseconds}',
        e,
        s,
      );
      rethrow;
    } finally {
      try {
        await channel.close();
      } on Object catch (e, s) {
        // Cleanup must not replace a confirmed receipt or the original error.
        LoggerService.warning(
          'event=ipc_scheduler_close_failed command=$command',
          e,
          s,
        );
      }
    }
  }

  Future<String> _replyShowWindow() async {
    final callback = _onShowWindow;
    if (callback == null) {
      LoggerService.info(
        'event=ipc_show_window_unavailable reason=no_callback '
        'ownerRole=$_role',
      );
      return SingleInstanceConfig.ipcShowWindowUnavailableMessage;
    }

    try {
      final shown = await IpcShowWindowConfirmation.runAttempt(callback);
      if (shown) {
        return SingleInstanceConfig.ipcOkAckMessage;
      }
      LoggerService.info(
        'event=ipc_show_window_unavailable reason=window_not_shown '
        'ownerRole=$_role',
      );
      return SingleInstanceConfig.ipcShowWindowUnavailableMessage;
    } on Object catch (e, s) {
      LoggerService.error('Erro no callback SHOW_WINDOW', e, s);
      return SingleInstanceConfig.ipcShowWindowUnavailableMessage;
    }
  }

  @override
  Future<SingleInstanceShowWindowStatus> notifyExistingInstance() async {
    final channel = await _connect(
      timeout: SingleInstanceConfig.showWindowConnectTimeout,
    );
    if (channel == null) {
      LoggerService.warning('ipc_show_window_failed connect');
      return SingleInstanceShowWindowStatus.notDelivered;
    }
    try {
      await _write(channel, SingleInstanceConfig.ipcShowWindowMessage);
      final ack = await channel.readLine(
        timeout: SingleInstanceConfig.showWindowResponseTimeout,
      );
      if (IpcV1Codec.isOkAck(ack)) {
        LoggerService.info('ipc_show_window_sent');
        return SingleInstanceShowWindowStatus.shown;
      }
      if (IpcV1Codec.isShowWindowUnavailable(ack)) {
        LoggerService.info('event=ipc_show_window_unavailable_ack');
        return SingleInstanceShowWindowStatus.unavailable;
      }
      LoggerService.debug('ipc_show_window_no_ack');
      return SingleInstanceShowWindowStatus.notDelivered;
    } on Object catch (_) {
      return SingleInstanceShowWindowStatus.notDelivered;
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
      await _write(channel, SingleInstanceConfig.ipcGetUserInfoMessage);
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
      await _write(channel, SingleInstanceConfig.ipcPingMessage);
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
      await _write(
        channel,
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
  Future<void> stop() => _serializeLifecycle(_stop);

  Future<void> _stop() async {
    scheduler = null;
    _onShowWindow = null;
    _onRunSchedule = null;
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
