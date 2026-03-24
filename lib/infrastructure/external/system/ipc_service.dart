import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/windows_user_service.dart';
import 'package:backup_database/domain/services/i_ipc_service.dart';

class IpcService implements IIpcService {
  ServerSocket? _server;
  Function()? _onShowWindow;
  bool _isRunning = false;
  int _currentPort = SingleInstanceConfig.ipcBasePort;

  static int? _cachedActivePort;
  static DateTime? _cachedActivePortAt;

  @override
  Future<bool> startServer({Function()? onShowWindow}) async {
    if (_isRunning) {
      LoggerService.debug('IPC Server ja esta rodando');
      return true;
    }

    _onShowWindow = onShowWindow;

    final portsToTry = _getPortsToTry();

    for (final port in portsToTry) {
      try {
        LoggerService.debug(
          'ipc_listen_try port=$port processRole=ui',
        );
        _server = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        _currentPort = port;
        _markActivePort(port);
        _isRunning = true;

        LoggerService.info(
          'IPC Server iniciado na porta $_currentPort '
          'protocol=${SingleInstanceConfig.ipcProtocolId}',
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
            LoggerService.info(
              'ipc_cmd SHOW_WINDOW processRole=ui',
            );
            _onShowWindow?.call();
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
        socket.close();
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
          timeout: SingleInstanceConfig.connectionTimeout,
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
          timeout: SingleInstanceConfig.connectionTimeout,
        );

        socket.add(utf8.encode(SingleInstanceConfig.ipcGetUserInfoMessage));
        await socket.flush();

        final data = await socket.first.timeout(
          SingleInstanceConfig.connectionTimeout,
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
    final defaultPorts = [
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

  static String _buildV1PongLine() {
    return '${SingleInstanceConfig.ipcPongLinePrefix}'
        'v=${SingleInstanceConfig.ipcProtocolVersion}|'
        'role=${SingleInstanceConfig.ipcInstanceRoleUi}|'
        'pid=$pid';
  }

  static String _buildV1UserInfoLine(String username) {
    final u64 = base64Url.encode(utf8.encode(username));
    return '${SingleInstanceConfig.ipcUserInfoLinePrefix}'
        'v=${SingleInstanceConfig.ipcProtocolVersion}|'
        'role=${SingleInstanceConfig.ipcInstanceRoleUi}|'
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
    if (!response.contains('role=${SingleInstanceConfig.ipcInstanceRoleUi}')) {
      return false;
    }
    if (!response.contains('pid=')) {
      return false;
    }
    return true;
  }

  static String? _parseUserInfoResponse(String message) {
    if (message.startsWith(SingleInstanceConfig.ipcUserInfoLinePrefix)) {
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
}
