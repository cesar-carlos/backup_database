import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/logging.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/connection/connected_client.dart';
import 'package:backup_database/infrastructure/datasources/daos/connection_log_dao.dart';
import 'package:backup_database/infrastructure/datasources/daos/server_credential_dao.dart';
import 'package:backup_database/infrastructure/protocol/binary_protocol.dart';
import 'package:backup_database/infrastructure/protocol/compression.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/socket/server/client_handler.dart';
import 'package:backup_database/infrastructure/socket/server/client_manager.dart';
import 'package:backup_database/infrastructure/socket/server/file_transfer_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/metrics_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/server_authentication.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';

class TcpSocketServer implements SocketServerService {
  TcpSocketServer({
    BinaryProtocol? protocol,
    ServerCredentialDao? serverCredentialDao,
    ClientManager? clientManager,
    ConnectionLogDao? connectionLogDao,
    ScheduleMessageHandler? scheduleHandler,
    FileTransferMessageHandler? fileTransferHandler,
    MetricsMessageHandler? metricsHandler,
    SocketLoggerService? socketLogger,
  }) : _protocol =
           protocol ?? BinaryProtocol(compression: PayloadCompression()),
       _authentication = serverCredentialDao != null
           ? ServerAuthentication(serverCredentialDao)
           : null,
       _clientManager = clientManager,
       _connectionLogDao = connectionLogDao,
       _scheduleHandler = scheduleHandler,
       _fileTransferHandler = fileTransferHandler,
       _metricsHandler = metricsHandler,
       _socketLogger = socketLogger ?? di.getIt<SocketLoggerService>();

  final BinaryProtocol _protocol;
  final ServerAuthentication? _authentication;
  final ClientManager? _clientManager;
  final ConnectionLogDao? _connectionLogDao;
  final ScheduleMessageHandler? _scheduleHandler;
  final FileTransferMessageHandler? _fileTransferHandler;
  final MetricsMessageHandler? _metricsHandler;
  final SocketLoggerService _socketLogger;
  ServerSocket? _serverSocket;
  int _port = SocketConfig.defaultPort;
  bool _isRunning = false;
  final Map<String, ClientHandler> _handlers = {};
  final Map<String, DateTime> _connectedAt = {};
  StreamController<Message> _messageController =
      StreamController<Message>.broadcast();

  @override
  bool get isRunning => _isRunning;

  @override
  int get port => _port;

  @override
  Stream<Message> get messageStream => _messageController.stream;

  @override
  Future<void> start({int port = 9527}) async {
    if (_isRunning) {
      LoggerService.debug('Socket Server already running');
      return;
    }

    _port = port;
    if (_messageController.isClosed) {
      _messageController = StreamController<Message>.broadcast();
    }
    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _port,
      );
      _isRunning = true;
      LoggerService.info('Socket Server started on port $_port');

      _serverSocket!.listen(
        _onConnection,
        onError: (error) {
          LoggerService.error('Socket Server accept error', error);
        },
        onDone: () {
          _isRunning = false;
          LoggerService.info('Socket Server stopped');
        },
      );
    } on SocketException catch (e) {
      LoggerService.error('Socket Server bind failed: ${e.message}', e);
      rethrow;
    }
  }

  void _onConnection(Socket socket) {
    final handler = ClientHandler(
      socket: socket,
      protocol: _protocol,
      onDisconnect: _onDisconnect,
      authentication: _authentication,
      connectionLogDao: _connectionLogDao,
      socketLogger: _socketLogger,
    );
    final clientId = handler.clientId;
    final connectedAt = DateTime.now();
    if (_clientManager != null) {
      _clientManager.register(handler, connectedAt);
    } else {
      _connectedAt[clientId] = connectedAt;
      _handlers[clientId] = handler;
    }

    handler.messageStream.listen(
      (Message msg) {
        _messageController.add(msg);
        _scheduleHandler?.handle(clientId, msg, sendToClient);
        _fileTransferHandler?.handle(clientId, msg, sendToClient);
        _metricsHandler?.handle(clientId, msg, sendToClient);
      },
      onError: (e) => LoggerService.warning('Handler stream error: $e'),
    );
    handler.start();
    LoggerService.info('Client connected: $clientId');
  }

  void _onDisconnect(String clientId) {
    if (_clientManager != null) {
      _clientManager.unregister(clientId);
    } else {
      _handlers.remove(clientId);
      _connectedAt.remove(clientId);
    }
    LoggerService.info('Client disconnected: $clientId');
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;

    _scheduleHandler?.dispose();

    if (_clientManager != null) {
      _clientManager.disconnectAll();
    } else {
      final handlers = _handlers.values.toList();
      for (final handler in handlers) {
        handler.disconnect();
      }
      _handlers.clear();
      _connectedAt.clear();
    }
    await _serverSocket?.close();
    _serverSocket = null;
    _isRunning = false;
    if (!_messageController.isClosed) {
      _messageController.close();
    }
    LoggerService.info('Socket Server stopped');
  }

  @override
  Future<void> restart() async {
    await stop();
    await Future<void>.delayed(const Duration(seconds: 1));
    await start(port: _port);
  }

  @override
  Future<List<ConnectedClient>> getConnectedClients() async {
    if (_clientManager != null) {
      return _clientManager.getConnectedClients();
    }
    final clients = <ConnectedClient>[];
    for (final entry in _handlers.entries) {
      final connectedAt = _connectedAt[entry.key] ?? DateTime.now();
      clients.add(entry.value.toConnectedClient(connectedAt));
    }
    return clients;
  }

  @override
  Future<void> disconnectClient(String clientId) async {
    if (_clientManager != null) {
      return _clientManager.disconnectClient(clientId);
    }
    final handler = _handlers[clientId];
    if (handler != null) {
      handler.disconnect();
    }
  }

  @override
  Future<void> broadcastToAll(Message message) async {
    final handlers = _clientManager != null
        ? _clientManager.getHandlers()
        : _handlers.values.toList();
    for (final handler in handlers) {
      try {
        await handler.send(message);
      } on Object catch (e) {
        LoggerService.warning('broadcastToAll send error: $e');
      }
    }
  }

  @override
  Future<void> sendToClient(String clientId, Message message) async {
    final handler = _clientManager?.getHandler(clientId) ?? _handlers[clientId];
    if (handler == null) {
      LoggerService.warning('sendToClient: client not found: $clientId');
      return;
    }
    await handler.send(message);
  }
}
