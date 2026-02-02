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

  @override
  Future<bool> startServer({Function()? onShowWindow}) async {
    if (_isRunning) {
      LoggerService.debug('IPC Server já está rodando');
      return true;
    }

    _onShowWindow = onShowWindow;

    final portsToTry = [
      SingleInstanceConfig.ipcBasePort,
      ...SingleInstanceConfig.ipcAlternativePorts,
    ];

    for (final port in portsToTry) {
      try {
        LoggerService.debug('Tentando iniciar IPC Server na porta $port...');
        _server = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        _currentPort = port;
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
            'Porta $port não disponível (${e.osError?.errorCode}), tentando próxima...',
          );
          continue;
        } else {
          LoggerService.warning(
            'Erro ao tentar porta $port: ${e.message}',
          );
          continue;
        }
      } on Object catch (e) {
        LoggerService.warning(
          'Erro inesperado ao tentar porta $port: $e',
        );
        continue;
      }
    }

    LoggerService.error(
      'Não foi possível iniciar IPC Server em nenhuma porta tentada. '
      'Tentativas: ${portsToTry.join(", ")}',
    );
    _isRunning = false;
    return false;
  }

  void _handleConnection(Socket socket) {
    LoggerService.debug('Nova conexão IPC recebida');

    socket.listen(
      (data) async {
        try {
          final message = utf8.decode(data).trim();
          LoggerService.debug('Mensagem IPC recebida: $message');

          if (message == SingleInstanceConfig.showWindowCommand) {
            LoggerService.info('Comando SHOW_WINDOW recebido via IPC');
            _onShowWindow?.call();
          } else if (message == SingleInstanceConfig.getUserInfoCommand) {
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
          }
        } on Object catch (e) {
          LoggerService.error('Erro ao processar mensagem IPC', e);
        }
      },
      onError: (error) {
        LoggerService.error('Erro na conexão IPC', error);
      },
      onDone: () {
        socket.close();
      },
    );
  }

  /// Sends a SHOW_WINDOW command to an existing instance.
  static Future<bool> sendShowWindow() async {
    final portsToTry = [
      SingleInstanceConfig.ipcBasePort,
      ...SingleInstanceConfig.ipcAlternativePorts,
    ];

    for (final port in portsToTry) {
      try {
        LoggerService.debug(
          'Tentando enviar comando SHOW_WINDOW na porta $port...',
        );

        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: SingleInstanceConfig.connectionTimeout,
        );

        socket.add(utf8.encode(SingleInstanceConfig.showWindowCommand));
        await socket.flush();

        await Future.delayed(SingleInstanceConfig.socketCloseDelay);
        await socket.close();

        LoggerService.info(
          'Comando SHOW_WINDOW enviado com sucesso na porta $port',
        );
        return true;
      } on Object catch (e) {
        LoggerService.debug('Porta $port não disponível, tentando próxima...');
        continue;
      }
    }

    LoggerService.warning(
      'Não foi possível enviar comando IPC em nenhuma porta tentada',
    );
    return false;
  }

  /// Checks if an IPC server is already running.
  static Future<bool> checkServerRunning() async {
    final portsToTry = [
      SingleInstanceConfig.ipcBasePort,
      ...SingleInstanceConfig.ipcAlternativePorts,
    ];

    for (final port in portsToTry) {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: SingleInstanceConfig.quickConnectionTimeout,
        );

        await socket.close();
        return true;
      } on Object catch (e) {
        continue;
      }
    }

    return false;
  }

  /// Gets the username of the user running the existing instance.
  static Future<String?> getExistingInstanceUser() async {
    final portsToTry = [
      SingleInstanceConfig.ipcBasePort,
      ...SingleInstanceConfig.ipcAlternativePorts,
    ];

    for (final port in portsToTry) {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: SingleInstanceConfig.connectionTimeout,
        );

        socket.add(utf8.encode(SingleInstanceConfig.getUserInfoCommand));
        await socket.flush();

        final completer = Completer<String?>();

        socket.listen(
          (data) {
            final message = utf8.decode(data).trim();
            if (message.startsWith(
              SingleInstanceConfig.userInfoResponsePrefix,
            )) {
              final username = message.substring(
                SingleInstanceConfig.userInfoResponsePrefix.length,
              );
              if (!completer.isCompleted) {
                completer.complete(username);
              }
            }
          },
          onDone: () {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
            socket.close();
          },
          onError: (e) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          },
        );

        final result = await completer.future.timeout(
          SingleInstanceConfig.connectionTimeout,
          onTimeout: () => null,
        );

        if (result != null) {
          return result;
        }
      } on Object catch (e) {
        continue;
      }
    }

    LoggerService.debug(
      'Não foi possível obter usuário da instância existente',
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
}
