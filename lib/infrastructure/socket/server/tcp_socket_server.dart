import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/logging.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/connection/connected_client.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:backup_database/infrastructure/datasources/daos/connection_log_dao.dart';
import 'package:backup_database/infrastructure/datasources/daos/server_credential_dao.dart';
import 'package:backup_database/infrastructure/protocol/binary_protocol.dart';
import 'package:backup_database/infrastructure/protocol/compression.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/socket/server/capabilities_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/client_handler.dart';
import 'package:backup_database/infrastructure/socket/server/client_manager.dart';
import 'package:backup_database/infrastructure/socket/server/file_transfer_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/health_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/metrics_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/preflight_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/server_authentication.dart';
import 'package:backup_database/infrastructure/socket/server/session_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';

class TcpSocketServer implements SocketServerService {
  TcpSocketServer({
    BinaryProtocol? protocol,
    ServerCredentialDao? serverCredentialDao,
    ILicenseValidationService? licenseValidationService,
    ClientManager? clientManager,
    ConnectionLogDao? connectionLogDao,
    ScheduleMessageHandler? scheduleHandler,
    FileTransferMessageHandler? fileTransferHandler,
    MetricsMessageHandler? metricsHandler,
    CapabilitiesMessageHandler? capabilitiesHandler,
    HealthMessageHandler? healthHandler,
    SessionMessageHandler? sessionHandler,
    PreflightMessageHandler? preflightHandler,
    SocketLoggerService? socketLogger,
  }) : _protocol =
           protocol ?? BinaryProtocol(compression: PayloadCompression()),
       _authentication = serverCredentialDao != null
           ? ServerAuthentication(
               serverCredentialDao,
               licenseValidationService: licenseValidationService,
             )
           : null,
       _clientManager = clientManager,
       _connectionLogDao = connectionLogDao,
       _scheduleHandler = scheduleHandler,
       _fileTransferHandler = fileTransferHandler,
       _metricsHandler = metricsHandler,
       _capabilitiesHandler =
           capabilitiesHandler ?? CapabilitiesMessageHandler(),
       _healthHandler = healthHandler ?? HealthMessageHandler(),
       _preflightHandler = preflightHandler ?? PreflightMessageHandler(),
       _socketLogger = socketLogger ?? di.getIt<SocketLoggerService>() {
    // SessionMessageHandler precisa consultar handlers vivos para
    // reportar a sessao do cliente. Construido aqui (em vez de no
    // initializer list) porque depende de `this` para o lookup.
    _sessionHandler = sessionHandler ??
        SessionMessageHandler(sessionLookup: _lookupSessionInfo);
  }

  final BinaryProtocol _protocol;
  final ServerAuthentication? _authentication;
  final ClientManager? _clientManager;
  final ConnectionLogDao? _connectionLogDao;
  final ScheduleMessageHandler? _scheduleHandler;
  final FileTransferMessageHandler? _fileTransferHandler;
  final MetricsMessageHandler? _metricsHandler;
  final CapabilitiesMessageHandler _capabilitiesHandler;
  final HealthMessageHandler _healthHandler;
  late final SessionMessageHandler _sessionHandler;
  final PreflightMessageHandler _preflightHandler;
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
        // Capabilities sempre disponivel (sem dependencias externas).
        // Permite ao cliente negociar features apos auth (M4.1).
        _capabilitiesHandler.handle(clientId, msg, sendToClient);
        // Health: cliente pode consultar saude do servidor antes de
        // operar. Sempre disponivel (sem deps externas hard) — checks
        // adicionais sao injetados no construtor (M1.10 / PR-1).
        _healthHandler.handle(clientId, msg, sendToClient);
        // Session: cliente pode confirmar identidade percebida pelo
        // servidor. Lookup pega snapshot do ClientHandler vivo.
        _sessionHandler.handle(clientId, msg, sendToClient);
        // Preflight: cliente pode validar prerequisitos profundos
        // (ferramenta de compactacao, pasta temp, espaco) antes de
        // disparar backup remoto (F1.8 do plano).
        _preflightHandler.handle(clientId, msg, sendToClient);
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

  /// Lookup usado pelo `SessionMessageHandler`. Retorna o snapshot da
  /// sessao para o `clientId` informado, ou `null` quando o cliente ja
  /// foi desregistrado (race condition entre `sessionRequest` e
  /// `disconnect`).
  Future<SessionInfo?> _lookupSessionInfo(String clientId) async {
    final handler =
        _clientManager?.getHandler(clientId) ?? _handlers[clientId];
    if (handler == null) return null;
    final connectedAt = _clientManager != null
        ? _clientManager.getConnectedAt(clientId)
        : _connectedAt[clientId];
    return SessionInfo(
      clientId: handler.clientId,
      isAuthenticated: handler.isAuthenticated,
      host: handler.host,
      port: handler.port,
      connectedAt: connectedAt ?? DateTime.now(),
      serverId: handler.authenticatedServerId,
    );
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
