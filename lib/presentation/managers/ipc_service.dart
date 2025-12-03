import 'dart:async';
import 'dart:io';

import '../../core/utils/logger_service.dart';

/// Serviço de Comunicação Inter-Processos (IPC)
/// Permite que múltiplas instâncias do aplicativo se comuniquem
class IpcService {
  static const int _port = 58724; // Porta fixa para IPC local
  static const String _showWindowCommand = 'SHOW_WINDOW';
  
  ServerSocket? _server;
  Function()? _onShowWindow;
  bool _isRunning = false;

  /// Inicia o servidor IPC que escuta por comandos de outras instâncias
  Future<bool> startServer({Function()? onShowWindow}) async {
    if (_isRunning) {
      LoggerService.debug('IPC Server já está rodando');
      return true;
    }

    _onShowWindow = onShowWindow;

    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);
      _isRunning = true;
      
      LoggerService.info('IPC Server iniciado na porta $_port');
      
      // Escutar conexões
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
    } catch (e) {
      LoggerService.error('Erro ao iniciar IPC Server', e);
      _isRunning = false;
      return false;
    }
  }

  /// Trata conexões recebidas de outras instâncias
  void _handleConnection(Socket socket) {
    LoggerService.debug('Nova conexão IPC recebida');
    
    socket.listen(
      (data) {
        try {
          final message = String.fromCharCodes(data).trim();
          LoggerService.debug('Mensagem IPC recebida: $message');
          
          if (message == _showWindowCommand) {
            LoggerService.info('Comando SHOW_WINDOW recebido via IPC');
            _onShowWindow?.call();
          }
        } catch (e) {
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

  /// Envia comando para a instância existente mostrar a janela
  static Future<bool> sendShowWindow() async {
    try {
      LoggerService.info('Enviando comando SHOW_WINDOW via IPC...');
      
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _port,
        timeout: const Duration(seconds: 2),
      );
      
      socket.write(_showWindowCommand);
      await socket.flush();
      
      await Future.delayed(const Duration(milliseconds: 100));
      await socket.close();
      
      LoggerService.info('Comando SHOW_WINDOW enviado com sucesso');
      return true;
    } catch (e) {
      LoggerService.warning('Não foi possível enviar comando IPC: $e');
      return false;
    }
  }

  /// Verifica se já existe uma instância rodando tentando conectar no servidor
  static Future<bool> checkServerRunning() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _port,
        timeout: const Duration(seconds: 1),
      );
      
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Encerra o servidor IPC
  Future<void> stop() async {
    if (_server != null) {
      try {
        await _server!.close();
        _isRunning = false;
        LoggerService.info('IPC Server parado');
      } catch (e) {
        LoggerService.error('Erro ao parar IPC Server', e);
      }
    }
  }

  bool get isRunning => _isRunning;
}

