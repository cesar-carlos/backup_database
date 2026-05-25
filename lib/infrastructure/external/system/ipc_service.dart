import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/windows_user_service.dart';
import 'package:backup_database/domain/services/i_ipc_service.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:meta/meta.dart';

class IpcService implements IIpcService {
  ServerSocket? _server;
  Function()? _onShowWindow;
  RunScheduleIpcHandler? _onRunSchedule;
  bool _isRunning = false;
  int _currentPort = SingleInstanceConfig.ipcBasePort;
  String _role = SingleInstanceConfig.ipcInstanceRoleUi;

  static int? _cachedActivePort;
  static DateTime? _cachedActivePortAt;

  static List<int>? _ipcPortsOverrideForTests;

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

    _role = _normalizeRole(role);
    _onShowWindow = onShowWindow;
    _onRunSchedule = onRunSchedule;

    final portsToTry = _getPortsToTry();

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
        _markActivePort(port);
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
            final scheduleId = _parseRunScheduleRequest(message);
            final result = scheduleId == null
                ? const SingleInstanceScheduledDelegationResult(
                    exitCode: 2,
                    message: SingleInstanceConfig
                        .ipcRunScheduleMessageInvalidScheduleId,
                  )
                : await _runDelegatedSchedule(scheduleId);
            socket.add(
              utf8.encode(
                _buildRunScheduleResultLine(
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
            final line = _buildV1UserInfoLine(username);
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
            socket.add(utf8.encode(_buildV1PongLine()));
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
    final portsToTry = _getPortsToTry();

    for (final port in portsToTry) {
      Socket? socket;
      try {
        LoggerService.debug('ipc_show_window_try port=$port');

        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: SingleInstanceConfig.ipcConnectTimeout,
        );

        socket.add(utf8.encode(SingleInstanceConfig.ipcShowWindowMessage));
        await socket.flush();

        await Future.delayed(SingleInstanceConfig.socketCloseDelay);
        await socket.close();
        _markActivePort(port);

        LoggerService.info('ipc_show_window_sent port=$port');
        return true;
      } on Object catch (_) {
        LoggerService.debug('ipc_show_window_miss port=$port');
      } finally {
        await _closeClientResources(socket: socket);
      }
    }

    LoggerService.warning(
      'ipc_show_window_failed ports_tried=${portsToTry.length}',
    );
    return false;
  }

  static Future<bool> checkServerRunning() async {
    final portsToTry = _getPortsToTry();
    final firstRoundCount = portsToTry.length > 2 ? 2 : portsToTry.length;
    final firstRoundPorts = portsToTry.take(firstRoundCount).toList();

    final firstRoundResult = await _checkPortsWithTimeout(
      ports: firstRoundPorts,
      timeout: SingleInstanceConfig.ipcDiscoveryFastTimeout,
    );
    if (firstRoundResult) {
      return true;
    }

    final remainingPorts = portsToTry.skip(firstRoundCount).toList();
    if (remainingPorts.isEmpty) {
      return false;
    }

    return _checkPortsWithTimeout(
      ports: remainingPorts,
      timeout: SingleInstanceConfig.ipcDiscoverySlowTimeout,
    );
  }

  static Future<String?> getExistingInstanceUser() async {
    final portsToTry = _getPortsToTry();

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
        final user = _parseUserInfoResponse(message);
        if (user != null) {
          _markActivePort(port);
          LoggerService.debug('ipc_user_resolved port=$port');
          return user;
        }
        LoggerService.debug('ipc_user_invalid_response port=$port');
        return null;
      } on Object catch (_) {
        continue;
      } finally {
        await _closeClientResources(socket: socket);
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
    final portsToTry = _getPortsToTry();

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
        final ownerInfo = _parseOwnerInfoFromV1Pong(response);
        if (ownerInfo != null) {
          _markActivePort(port);
          LoggerService.infoWithContext(
            'event=ipc_owner_info_resolved ownerRole=${ownerInfo.role} '
            'canRunSchedule=${ownerInfo.canRunSchedule}',
          );
          return ownerInfo;
        }
      } on Object catch (_) {
        continue;
      } finally {
        await _closeClientResources(socket: socket);
      }
    }

    LoggerService.debug('ipc_owner_info_unresolved');
    return null;
  }

  static Future<SingleInstanceScheduledDelegationResult?>
  delegateScheduledExecution(String scheduleId) async {
    final portsToTry = _getPortsToTry();

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
        final result = _parseRunScheduleResult(response);
        if (result != null) {
          _markActivePort(port);
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
        await _closeClientResources(socket: socket);
      }
    }

    LoggerService.warning(
      'ipc_run_schedule_failed ports_tried=${portsToTry.length}',
    );
    return null;
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

  /// Port bound by [startServer], or [SingleInstanceConfig.ipcBasePort] before listen.
  int get listenPort => _currentPort;

  @visibleForTesting
  static List<int>? get ipcPortsOverrideForTests => _ipcPortsOverrideForTests;

  @visibleForTesting
  static set ipcPortsOverrideForTests(List<int>? ports) {
    _ipcPortsOverrideForTests = ports;
  }

  @visibleForTesting
  static void resetPortCacheForTests() {
    _cachedActivePort = null;
    _cachedActivePortAt = null;
    _ipcPortsOverrideForTests = null;
  }

  static Future<void> _closeClientResources({
    Socket? socket,
  }) async {
    if (socket != null) {
      try {
        await socket.close();
      } on Object catch (_) {
        try {
          socket.destroy();
        } on Object catch (_) {}
      }
    }
  }

  static List<int> _getPortsToTry() {
    final defaultPorts =
        _ipcPortsOverrideForTests ??
        [
          SingleInstanceConfig.ipcBasePort,
          ...SingleInstanceConfig.ipcAlternativePorts,
        ];
    final cachedPort = _getCachedActivePortIfFresh();
    if (cachedPort == null) {
      return defaultPorts;
    }

    return [cachedPort, ...defaultPorts.where((port) => port != cachedPort)];
  }

  static int? _getCachedActivePortIfFresh() {
    final cachedPort = _cachedActivePort;
    final cachedAt = _cachedActivePortAt;
    if (cachedPort == null || cachedAt == null) {
      return null;
    }

    final cacheAge = DateTime.now().difference(cachedAt);
    if (cacheAge <= SingleInstanceConfig.ipcPortCacheTtl) {
      LoggerService.debug(
        'ipc_port_cache_hit port=$cachedPort '
        'age_ms=${cacheAge.inMilliseconds}',
      );
      return cachedPort;
    }

    _cachedActivePort = null;
    _cachedActivePortAt = null;
    return null;
  }

  static void _markActivePort(int port) {
    _cachedActivePort = port;
    _cachedActivePortAt = DateTime.now();
  }

  static Future<bool> _checkPortsWithTimeout({
    required List<int> ports,
    required Duration timeout,
  }) async {
    final results = await Future.wait(
      ports.map((port) => _probeServerPort(port: port, timeout: timeout)),
    );
    return results.any((bool isActive) => isActive);
  }

  static Future<bool> _probeServerPort({
    required int port,
    required Duration timeout,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: timeout,
      );

      socket.add(utf8.encode(SingleInstanceConfig.ipcPingMessage));
      await socket.flush();

      final data = await socket.first.timeout(timeout);
      final response = utf8.decode(data).trim();
      if (_isValidV1Pong(response)) {
        _markActivePort(port);
        LoggerService.debug('ipc_probe_ok port=$port');
        return true;
      }

      LoggerService.debug('ipc_probe_invalid_pong port=$port');
      return false;
    } on Object catch (_) {
      return false;
    } finally {
      await _closeClientResources(socket: socket);
    }
  }

  bool get _canRunSchedule => _onRunSchedule != null;

  Future<SingleInstanceScheduledDelegationResult> _runDelegatedSchedule(
    String scheduleId,
  ) async {
    final handler = _onRunSchedule;
    if (handler == null) {
      LoggerService.warning(
        'event=ipc_run_schedule_no_handler ownerRole=$_role',
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

  static String _normalizeRole(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized == SingleInstanceConfig.ipcInstanceRoleService) {
      return SingleInstanceConfig.ipcInstanceRoleService;
    }
    return SingleInstanceConfig.ipcInstanceRoleUi;
  }

  static String? _parseRunScheduleRequest(String message) {
    final match = RegExp(r'(?:^|\|)scheduleId=([^|\s]+)').firstMatch(message);
    return match?.group(1);
  }

  static String _buildRunScheduleResultLine({
    required int exitCode,
    String? message,
  }) {
    final buffer =
        StringBuffer(SingleInstanceConfig.ipcRunScheduleResultLinePrefix)
          ..write('v=${SingleInstanceConfig.ipcProtocolVersion}|')
          ..write('exitCode=$exitCode');
    if (message != null && message.isNotEmpty) {
      buffer.write('|message64=${base64Url.encode(utf8.encode(message))}');
    }
    return buffer.toString();
  }

  static SingleInstanceScheduledDelegationResult? _parseRunScheduleResult(
    String message,
  ) {
    if (!message.startsWith(
      SingleInstanceConfig.ipcRunScheduleResultLinePrefix,
    )) {
      return null;
    }
    if (!message.contains('v=${SingleInstanceConfig.ipcProtocolVersion}')) {
      return null;
    }
    final exitMatch = RegExp(r'(?:^|\|)exitCode=(-?\d+)').firstMatch(message);
    final exitCode = int.tryParse(exitMatch?.group(1) ?? '');
    if (exitCode == null) {
      return null;
    }
    String? decodedMessage;
    final messageMatch = RegExp(r'(?:^|\|)message64=([^|\s]+)').firstMatch(
      message,
    );
    if (messageMatch != null) {
      try {
        decodedMessage = utf8.decode(base64Url.decode(messageMatch.group(1)!));
      } on Object {
        decodedMessage = null;
      }
    }
    return SingleInstanceScheduledDelegationResult(
      exitCode: exitCode,
      message: decodedMessage,
    );
  }

  String _buildV1PongLine() {
    return '${SingleInstanceConfig.ipcPongLinePrefix}'
        'v=${SingleInstanceConfig.ipcProtocolVersion}|'
        'role=$_role|'
        'canRunSchedule=$_canRunSchedule|'
        'pid=$pid';
  }

  String _buildV1UserInfoLine(String username) {
    final u64 = base64Url.encode(utf8.encode(username));
    return '${SingleInstanceConfig.ipcUserInfoLinePrefix}'
        'v=${SingleInstanceConfig.ipcProtocolVersion}|'
        'role=$_role|'
        'pid=$pid|'
        'u64=$u64';
  }

  static bool _isValidV1Pong(String response) {
    if (!response.startsWith(SingleInstanceConfig.ipcPongLinePrefix)) {
      return false;
    }
    if (!response.contains('v=${SingleInstanceConfig.ipcProtocolVersion}')) {
      return false;
    }
    final role = _parseRoleFromV1Line(response);
    if (role == null) {
      return false;
    }
    if (!response.contains('pid=')) {
      return false;
    }
    return true;
  }

  static SingleInstanceOwnerInfo? _parseOwnerInfoFromV1Pong(String response) {
    if (!_isValidV1Pong(response)) {
      return null;
    }
    final role = _parseRoleFromV1Line(response);
    if (role == null) {
      return null;
    }
    return SingleInstanceOwnerInfo(
      role: role,
      canRunSchedule: _parseBoolField(
        response,
        'canRunSchedule',
        defaultValue: false,
      ),
    );
  }

  static String? _parseUserInfoResponse(String message) {
    if (message.startsWith(SingleInstanceConfig.ipcUserInfoLinePrefix)) {
      if (!message.contains('v=${SingleInstanceConfig.ipcProtocolVersion}')) {
        return null;
      }
      if (_parseRoleFromV1Line(message) == null) {
        return null;
      }
      final match = RegExp(r'u64=([^|\s]+)').firstMatch(message);
      if (match == null) {
        return null;
      }
      try {
        return utf8.decode(base64Url.decode(match.group(1)!));
      } on Object {
        return null;
      }
    }

    if (message.startsWith(SingleInstanceConfig.userInfoResponsePrefix)) {
      return message.substring(
        SingleInstanceConfig.userInfoResponsePrefix.length,
      );
    }

    return null;
  }

  static String? _parseRoleFromV1Line(String message) {
    final match = RegExp(r'(?:^|\|)role=([^|\s]+)').firstMatch(message);
    final role = match?.group(1);
    if (role == SingleInstanceConfig.ipcInstanceRoleUi ||
        role == SingleInstanceConfig.ipcInstanceRoleService) {
      return role;
    }
    return null;
  }

  static bool _parseBoolField(
    String message,
    String fieldName, {
    required bool defaultValue,
  }) {
    final match = RegExp(
      '(?:^|\\|)$fieldName=([^|\\s]+)',
    ).firstMatch(message);
    final value = match?.group(1)?.toLowerCase();
    if (value == 'true') {
      return true;
    }
    if (value == 'false') {
      return false;
    }
    return defaultValue;
  }
}
