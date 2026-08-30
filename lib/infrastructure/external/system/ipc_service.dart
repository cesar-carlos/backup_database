import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/windows_user_service.dart';
import 'package:backup_database/domain/services/i_ipc_service.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_port_probe.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_schedule_delegator.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_v1_codec.dart';
import 'package:meta/meta.dart';

class IpcService implements IIpcService {
  ServerSocket? _server;
  Function()? _onShowWindow;
  RunScheduleIpcHandler? _onRunSchedule;
  bool _isRunning = false;
  int _currentPort = SingleInstanceConfig.ipcBasePort;
  String _role = SingleInstanceConfig.ipcInstanceRoleUi;
  late final IpcScheduleDelegator _scheduleDelegator = IpcScheduleDelegator(
    handler: () => _onRunSchedule,
    role: () => _role,
  );

  @override
  Future<bool> startServer({
    required String role,
    Function()? onShowWindow,
    RunScheduleIpcHandler? onRunSchedule,
  }) async {
    if (_isRunning) {
      LoggerService.debug('IPC Server ja esta rodando');
      return true;
    }

    _role = IpcV1Codec.normalizeRole(role);
    _onShowWindow = onShowWindow;
    _onRunSchedule = onRunSchedule;

    final portsToTry = IpcPortProbe.portsToTry();

    for (final port in portsToTry) {
      try {
        LoggerService.debug(
          'ipc_listen_try port=$port processRole=$_role',
        );
        _server = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        _currentPort = port;
        IpcPortProbe.markActive(port);
        _isRunning = true;

        LoggerService.infoWithContext(
          'event=ipc_server_started port=$_currentPort '
          'protocol=${SingleInstanceConfig.ipcProtocolId} ownerRole=$_role '
          'canRunSchedule=$_canRunSchedule',
        );

        _server!.listen(
          _handleConnection,
          onError: (Object error) {
            LoggerService.error('Erro no IPC Server', error);
          },
          onDone: () {
            LoggerService.info('IPC Server encerrado');
            _isRunning = false;
          },
        );

        return true;
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 10013 || e.osError?.errorCode == 10048) {
          LoggerService.debug(
            'ipc_listen_skip port=$port code=${e.osError?.errorCode}',
          );
          continue;
        }

        LoggerService.warning('Erro ao tentar porta $port: ${e.message}');
      } on Object catch (e) {
        LoggerService.warning('Erro inesperado ao tentar porta $port: $e');
      }
    }

    LoggerService.error(
      'Nao foi possivel iniciar IPC Server em nenhuma porta tentada. '
      'Tentativas: ${portsToTry.join(", ")}',
    );
    _isRunning = false;
    return false;
  }

  void _handleConnection(Socket socket) {
    LoggerService.debug('ipc_connection_open');

    socket.listen(
      (List<int> data) async {
        try {
          final message = utf8.decode(data).trim();
          LoggerService.debug('ipc_rx len=${message.length}');

          if (message == SingleInstanceConfig.showWindowCommand ||
              message == SingleInstanceConfig.ipcShowWindowMessage) {
            LoggerService.infoWithContext(
              'event=ipc_show_window_received ownerRole=$_role',
            );
            _onShowWindow?.call();
            return;
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
                    message: SingleInstanceConfig
                        .ipcRunScheduleMessageInvalidScheduleId,
                  )
                : await _scheduleDelegator.runDelegated(scheduleId);
            socket.add(
              utf8.encode(
                IpcV1Codec.buildRunScheduleResultLine(
                  exitCode: result.exitCode,
                  message: result.message,
                ),
              ),
            );
            await socket.flush();
            return;
          }

          if (message == SingleInstanceConfig.getUserInfoCommand ||
              message == SingleInstanceConfig.ipcGetUserInfoMessage) {
            LoggerService.debug('ipc_cmd GET_USER_INFO');
            final username =
                WindowsUserService.getCurrentUsername() ?? 'Desconhecido';
            final line = IpcV1Codec.buildV1UserInfoLine(
              username: username,
              role: _role,
            );
            socket.add(utf8.encode(line));
            await socket.flush();
            LoggerService.debug('ipc_tx USER_INFO ok');
            return;
          }

          if (message == SingleInstanceConfig.pingCommand) {
            LoggerService.debug('ipc_ping_legacy');
            socket.add(utf8.encode(SingleInstanceConfig.pongResponse));
            await socket.flush();
            return;
          }

          if (message == SingleInstanceConfig.ipcPingMessage) {
            LoggerService.debug('ipc_ping_v1');
            socket.add(
              utf8.encode(
                IpcV1Codec.buildV1PongLine(
                  role: _role,
                  canRunSchedule: _canRunSchedule,
                ),
              ),
            );
            await socket.flush();
            return;
          }
        } on Object catch (e) {
          LoggerService.error('Erro ao processar mensagem IPC', e);
        }
      },
      onError: (Object error) {
        LoggerService.error('Erro na conexao IPC', error);
      },
      onDone: () {
        unawaited(socket.close());
      },
    );
  }

  static Future<bool> sendShowWindow() async {
    final portsToTry = IpcPortProbe.portsToTry();

    for (final port in portsToTry) {
      Socket? socket;
      try {
        LoggerService.debug('ipc_show_window_try port=$port');

        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: SingleInstanceConfig.showWindowConnectTimeout,
        );

        socket.add(utf8.encode(SingleInstanceConfig.ipcShowWindowMessage));
        await socket.flush();

        await Future.delayed(SingleInstanceConfig.socketCloseDelay);
        await socket.close();
        IpcPortProbe.markActive(port);

        LoggerService.info('ipc_show_window_sent port=$port');
        return true;
      } on Object catch (_) {
        LoggerService.debug('ipc_show_window_miss port=$port');
      } finally {
        await IpcPortProbe.closeClientResources(socket: socket);
      }
    }

    LoggerService.warning(
      'ipc_show_window_failed ports_tried=${portsToTry.length}',
    );
    return false;
  }

  static Future<bool> checkServerRunning() => IpcPortProbe.checkServerRunning();

  static Future<String?> getExistingInstanceUser() async {
    final portsToTry = IpcPortProbe.portsToTry();

    for (final port in portsToTry) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: SingleInstanceConfig.ipcConnectTimeout,
        );

        socket.add(utf8.encode(SingleInstanceConfig.ipcGetUserInfoMessage));
        await socket.flush();

        final data = await socket.first.timeout(
          SingleInstanceConfig.ipcConnectTimeout,
        );
        final message = utf8.decode(data).trim();
        final user = IpcV1Codec.parseUserInfoResponse(message);
        if (user != null) {
          IpcPortProbe.markActive(port);
          LoggerService.debug('ipc_user_resolved port=$port');
          return user;
        }
        LoggerService.debug('ipc_user_invalid_response port=$port');
        return null;
      } on Object catch (_) {
        continue;
      } finally {
        await IpcPortProbe.closeClientResources(socket: socket);
      }
    }

    LoggerService.debug('ipc_user_unresolved');
    return null;
  }

  static Future<String?> getExistingInstanceRole() async {
    final ownerInfo = await getExistingInstanceInfo();
    return ownerInfo?.role;
  }

  static Future<SingleInstanceOwnerInfo?> getExistingInstanceInfo() async {
    final portsToTry = IpcPortProbe.portsToTry();

    for (final port in portsToTry) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: SingleInstanceConfig.ipcConnectTimeout,
        );

        socket.add(utf8.encode(SingleInstanceConfig.ipcPingMessage));
        await socket.flush();

        final data = await socket.first.timeout(
          SingleInstanceConfig.ipcConnectTimeout,
        );
        final response = utf8.decode(data).trim();
        final ownerInfo = IpcV1Codec.parseOwnerInfoFromV1Pong(response);
        if (ownerInfo != null) {
          IpcPortProbe.markActive(port);
          LoggerService.infoWithContext(
            'event=ipc_owner_info_resolved ownerRole=${ownerInfo.role} '
            'canRunSchedule=${ownerInfo.canRunSchedule}',
          );
          return ownerInfo;
        }
      } on Object catch (_) {
        continue;
      } finally {
        await IpcPortProbe.closeClientResources(socket: socket);
      }
    }

    LoggerService.debug('ipc_owner_info_unresolved');
    return null;
  }

  static Future<SingleInstanceScheduledDelegationResult?>
  delegateScheduledExecution(String scheduleId) {
    return IpcScheduleDelegator.delegateToExistingInstance(scheduleId);
  }

  @override
  Future<void> stop() async {
    if (_server != null) {
      try {
        await _server!.close();
        _isRunning = false;
        LoggerService.info('IPC Server parado');
      } on Object catch (e) {
        LoggerService.error('Erro ao parar IPC Server', e);
      }
    }
  }

  @override
  bool get isRunning => _isRunning;

  int get listenPort => _currentPort;

  @visibleForTesting
  static List<int>? get ipcPortsOverrideForTests =>
      IpcPortProbe.portsOverrideForTests;

  @visibleForTesting
  static set ipcPortsOverrideForTests(List<int>? ports) {
    IpcPortProbe.portsOverrideForTests = ports;
  }

  @visibleForTesting
  static void resetPortCacheForTests() {
    IpcPortProbe.resetForTests();
  }

  bool get _canRunSchedule => _onRunSchedule != null;
}
