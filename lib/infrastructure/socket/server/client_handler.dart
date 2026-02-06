import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/logging/logging.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/connection/connected_client.dart';
import 'package:backup_database/infrastructure/datasources/daos/connection_log_dao.dart';
import 'package:backup_database/infrastructure/protocol/auth_messages.dart';
import 'package:backup_database/infrastructure/protocol/binary_protocol.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/socket/heartbeat.dart';
import 'package:backup_database/infrastructure/socket/server/server_authentication.dart';
import 'package:uuid/uuid.dart';

const int _headerSize = 16;
const int _checksumSize = 4;

class ClientHandler {
  ClientHandler({
    required Socket socket,
    required BinaryProtocol protocol,
    required void Function(String clientId) onDisconnect,
    ServerAuthentication? authentication,
    ConnectionLogDao? connectionLogDao,
    SocketLoggerService? socketLogger,
  }) : _socket = socket,
       _protocol = protocol,
       _onDisconnect = onDisconnect,
       _authentication = authentication,
       _connectionLogDao = connectionLogDao,
       _socketLogger = socketLogger,
       _clientId = const Uuid().v4() {
    _remoteAddress = _socket.remoteAddress.address;
    _remotePort = _socket.remotePort;
  }

  final Socket _socket;
  final BinaryProtocol _protocol;
  final void Function(String clientId) _onDisconnect;
  final ServerAuthentication? _authentication;
  final ConnectionLogDao? _connectionLogDao;
  final SocketLoggerService? _socketLogger;
  final String _clientId;
  bool _authHandled = false;

  late final String _remoteAddress;
  late final int _remotePort;

  final StreamController<Message> _messageController =
      StreamController<Message>.broadcast();
  final List<int> _buffer = [];
  bool isAuthenticated = false;
  String clientName = '';
  DateTime _lastHeartbeat = DateTime.now();
  HeartbeatManager? _heartbeatManager;

  Stream<Message> get messageStream => _messageController.stream;
  String get clientId => _clientId;
  String get host => _remoteAddress;
  int get port => _remotePort;
  DateTime get lastHeartbeat => _lastHeartbeat;

  void updateHeartbeat() => _lastHeartbeat = DateTime.now();

  ConnectedClient toConnectedClient(DateTime connectedAt) => ConnectedClient(
    id: _clientId,
    clientId: _clientId,
    clientName: clientName.isEmpty ? _remoteAddress : clientName,
    host: _remoteAddress,
    port: _remotePort,
    connectedAt: connectedAt,
    lastHeartbeat: _lastHeartbeat,
    isAuthenticated: isAuthenticated,
  );

  void start() {
    if (_authentication == null) {
      isAuthenticated = true;
    }
    _heartbeatManager = HeartbeatManager(
      sendHeartbeat: send,
      onTimeout: disconnect,
    );
    _heartbeatManager!.start();
    _socket.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  void _onData(List<int> data) {
    _buffer.addAll(data);
    _tryParseMessages();
  }

  void _tryParseMessages() {
    while (_buffer.length >= _headerSize) {
      final length = _readUint32Be(_buffer, 5);
      final totalNeeded = _headerSize + length + _checksumSize;
      if (_buffer.length < totalNeeded) break;

      final messageBytes = Uint8List.fromList(_buffer.sublist(0, totalNeeded));
      _buffer.removeRange(0, totalNeeded);

      try {
        final message = _protocol.deserializeMessage(messageBytes);

        // Log received message
        _socketLogger?.logReceived(message);

        if (isAuthRequestMessage(message) && !_authHandled) {
          _authHandled = true;
          if (_authentication != null) {
            _authentication.validateAuthRequest(message).then((
              bool valid,
            ) async {
              isAuthenticated = valid;
              final serverId = message.payload['serverId'] as String?;
              try {
                await _connectionLogDao?.insertConnectionAttempt(
                  clientHost: _remoteAddress,
                  serverId: serverId,
                  success: valid,
                  errorMessage: valid
                      ? null
                      : 'Invalid password or credential not found',
                  clientId: _clientId,
                );
              } on Object catch (e) {
                LoggerService.warning('ClientHandler: failed to log auth: $e');
              }
              await send(createAuthResponse(success: valid));
              if (!valid) {
                disconnect();
                return;
              }
              _messageController.add(message);
            });
            return;
          }
          isAuthenticated = true;
        } else if (isHeartbeatMessage(message)) {
          _heartbeatManager?.onHeartbeatReceived();
          _lastHeartbeat = DateTime.now();
        }
        _messageController.add(message);
      } on ProtocolException catch (e) {
        LoggerService.warning(
          'ClientHandler parse error for $_remoteAddress: ${e.message}',
        );
        unawaited(
          send(
            createErrorMessage(
              requestId: 0,
              errorMessage: 'Failed to parse message: ${e.message}',
              errorCode: ErrorCode.parseError,
            ),
          ),
        );
      }
    }
  }

  int _readUint32Be(List<int> data, int offset) {
    if (data.length < offset + 4) return 0;
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  void _onError(Object error, [StackTrace? stackTrace]) {
    LoggerService.warning(
      'ClientHandler error for $clientId: $error',
      error,
      stackTrace,
    );
  }

  void _onDone() {
    disconnect();
  }

  Future<void> send(Message message) async {
    try {
      final data = _protocol.serializeMessage(message);

      // Log sent message
      _socketLogger?.logSent(message);

      _socket.add(data);
      await _socket.flush();
    } on Object catch (e) {
      LoggerService.warning('ClientHandler send error: $e');
      rethrow;
    }
  }

  void disconnect() {
    _heartbeatManager?.stop();
    _heartbeatManager = null;
    if (!_messageController.isClosed) {
      _messageController.close();
    }
    _socket.destroy();
    _onDisconnect(_clientId);
  }
}
