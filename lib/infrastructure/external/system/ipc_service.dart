import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/windows_user_service.dart';
import 'package:backup_database/domain/services/i_ipc_service.dart';

/// Implementation of [IIpcService] using TCP sockets on localhost.
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
        LoggerService.debug('Tentando iniciar IPC Server na porta $port...');
        _server = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        _currentPort = port;
        _markActivePort(port);
        _isRunning = true;

        LoggerService.info('IPC Server iniciado na porta $_currentPort');

        _server!.listen(
          _handleConnection,
          onError: (error) {
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
            'Porta $port nao disponivel (${e.osError?.errorCode}), tentando proxima...',
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
    LoggerService.debug('Nova conexao IPC recebida');

    socket.listen(
      (data) async {
        try {
          final message = utf8.decode(data).trim();
          LoggerService.debug('Mensagem IPC recebida: $message');

          if (message == SingleInstanceConfig.showWindowCommand) {
            LoggerService.info('Comando SHOW_WINDOW recebido via IPC');
            _onShowWindow?.call();
            return;
          }

          if (message == SingleInstanceConfig.getUserInfoCommand) {
            LoggerService.debug('Comando GET_USER_INFO recebido via IPC');
            final username =
                WindowsUserService.getCurrentUsername() ?? 'Desconhecido';
            socket.add(
              utf8.encode(
                '${SingleInstanceConfig.userInfoResponsePrefix}$username',
              ),
            );
            await socket.flush();
            LoggerService.debug('Resposta USER_INFO enviada: $username');
            return;
          }

          if (message == SingleInstanceConfig.pingCommand) {
            LoggerService.debug('Comando PING recebido via IPC');
            socket.add(utf8.encode(SingleInstanceConfig.pongResponse));
            await socket.flush();
          }
        } on Object catch (e) {
          LoggerService.error('Erro ao processar mensagem IPC', e);
        }
      },
      onError: (error) {
        LoggerService.error('Erro na conexao IPC', error);
      },
      onDone: () {
        socket.close();
      },
    );
  }

  /// Sends a SHOW_WINDOW command to an existing instance.
  static Future<bool> sendShowWindow() async {
    final portsToTry = _getPortsToTry();

    for (final port in portsToTry) {
      Socket? socket;
      try {
        LoggerService.debug(
          'Tentando enviar comando SHOW_WINDOW na porta $port...',
        );

        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: SingleInstanceConfig.connectionTimeout,
        );

        socket.add(utf8.encode(SingleInstanceConfig.showWindowCommand));
        await socket.flush();

        await Future.delayed(SingleInstanceConfig.socketCloseDelay);
        await socket.close();
        _markActivePort(port);

        LoggerService.info(
          'Comando SHOW_WINDOW enviado com sucesso na porta $port',
        );
        return true;
      } on Object catch (_) {
        LoggerService.debug('Porta $port nao disponivel, tentando proxima...');
      } finally {
        await _closeClientResources(socket: socket);
      }
    }

    LoggerService.warning(
      'Nao foi possivel enviar comando IPC em nenhuma porta tentada',
    );
    return false;
  }

  /// Checks if an IPC server is already running.
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

  /// Gets the username of the user running the existing instance.
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

        socket.add(utf8.encode(SingleInstanceConfig.getUserInfoCommand));
        await socket.flush();

        final data = await socket.first.timeout(
          SingleInstanceConfig.connectionTimeout,
        );
        final message = utf8.decode(data).trim();
        if (message.startsWith(SingleInstanceConfig.userInfoResponsePrefix)) {
          _markActivePort(port);
          return message.substring(
            SingleInstanceConfig.userInfoResponsePrefix.length,
          );
        }
      } on Object catch (_) {
        continue;
      } finally {
        await _closeClientResources(socket: socket);
      }
    }

    LoggerService.debug(
      'Nao foi possivel obter usuario da instancia existente',
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
    return results.any((isActive) => isActive);
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

      socket.add(utf8.encode(SingleInstanceConfig.pingCommand));
      await socket.flush();

      final data = await socket.first.timeout(timeout);
      final response = utf8.decode(data).trim();
      if (response == SingleInstanceConfig.pongResponse) {
        _markActivePort(port);
        return true;
      }

      return false;
    } on Object catch (_) {
      return false;
    } finally {
      await _closeClientResources(socket: socket);
    }
  }
}
