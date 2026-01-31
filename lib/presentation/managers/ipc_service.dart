import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/windows_user_service.dart';

class IpcService {
  static const int _defaultPort = 58724;
  static const List<int> _alternativePorts = [
    58725,
    58726,
    58727,
    58728,
    58729,
  ];
  static const String _showWindowCommand = 'SHOW_WINDOW';
  static const String _getUserInfoCommand = 'GET_USER_INFO';
  static const String _userInfoResponsePrefix = 'USER_INFO:';

  static const Duration _connectionTimeout = Duration(seconds: 1);
  static const Duration _socketCloseDelay = Duration(milliseconds: 100);
  static const Duration _quickConnectionTimeout = Duration(milliseconds: 500);

  ServerSocket? _server;
  Function()? _onShowWindow;
  bool _isRunning = false;
  int _currentPort = _defaultPort;

  Future<bool> startServer({Function()? onShowWindow}) async {
    if (_isRunning) {
      LoggerService.debug('IPC Server já está rodando');
      return true;
    }

    _onShowWindow = onShowWindow;

    final portsToTry = [_defaultPort, ..._alternativePorts];

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
          final message = String.fromCharCodes(data).trim();
          LoggerService.debug('Mensagem IPC recebida: $message');

          if (message == _showWindowCommand) {
            LoggerService.info('Comando SHOW_WINDOW recebido via IPC');
            _onShowWindow?.call();
          } else if (message == _getUserInfoCommand) {
            LoggerService.debug('Comando GET_USER_INFO recebido via IPC');
            final username =
                WindowsUserService.getCurrentUsername() ?? 'Desconhecido';
            socket.write('$_userInfoResponsePrefix$username');
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

  static Future<bool> sendShowWindow() async {
    final portsToTry = [_defaultPort, ..._alternativePorts];

    for (final port in portsToTry) {
      try {
        LoggerService.debug(
          'Tentando enviar comando SHOW_WINDOW na porta $port...',
        );

        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: _connectionTimeout,
        );

        socket.write(_showWindowCommand);
        await socket.flush();

        await Future.delayed(_socketCloseDelay);
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

  static Future<bool> checkServerRunning() async {
    final portsToTry = [_defaultPort, ..._alternativePorts];

    for (final port in portsToTry) {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: _quickConnectionTimeout,
        );

        await socket.close();
        return true;
      } on Object catch (e) {
        continue;
      }
    }

    return false;
  }

  static Future<String?> getExistingInstanceUser() async {
    final portsToTry = [_defaultPort, ..._alternativePorts];

    for (final port in portsToTry) {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: _connectionTimeout,
        );

        socket.write(_getUserInfoCommand);
        await socket.flush();

        final completer = Completer<String?>();

        socket.listen(
          (data) {
            final message = String.fromCharCodes(data).trim();
            if (message.startsWith(_userInfoResponsePrefix)) {
              final username = message.substring(
                _userInfoResponsePrefix.length,
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
          _connectionTimeout,
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

  bool get isRunning => _isRunning;
}
