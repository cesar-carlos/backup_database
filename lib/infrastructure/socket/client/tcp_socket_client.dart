import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/security/password_hasher.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/auth_messages.dart';
import 'package:backup_database/infrastructure/protocol/binary_protocol.dart';
import 'package:backup_database/infrastructure/protocol/compression.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/socket/client/socket_client_service.dart';
import 'package:backup_database/infrastructure/socket/heartbeat.dart';

const int _headerSize = 16;
const int _checksumSize = 4;

class TcpSocketClient implements SocketClientService {
  TcpSocketClient({BinaryProtocol? protocol})
    : _protocol = protocol ?? BinaryProtocol(compression: PayloadCompression());

  final BinaryProtocol _protocol;
  Socket? _socket;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  final StreamController<Message> _messageController =
      StreamController<Message>.broadcast();
  final List<int> _buffer = [];
  StreamSubscription<List<int>>? _subscription;
  HeartbeatManager? _heartbeatManager;
  StreamSubscription<Message>? _heartbeatSubscription;
  bool _waitingAuth = false;

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  String? _reconnectHost;
  int? _reconnectPort;
  String? _reconnectServerId;
  String? _reconnectPassword;
  bool _reconnectEnabled = false;
  bool _disconnectRequested = false;

  @override
  bool get isConnected => _status == ConnectionStatus.connected;

  @override
  ConnectionStatus get status => _status;

  @override
  Stream<Message> get messageStream => _messageController.stream;

  @override
  Future<void> connect({
    required String host,
    required int port,
    String? serverId,
    String? password,
    bool enableAutoReconnect = false,
  }) async {
    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting) {
      LoggerService.debug('TcpSocketClient already connected or connecting');
      return;
    }

    _disconnectRequested = false;
    _reconnectEnabled = enableAutoReconnect;
    if (enableAutoReconnect) {
      _reconnectHost = host;
      _reconnectPort = port;
      _reconnectServerId = serverId;
      _reconnectPassword = password;
    }

    await _doConnect(host, port, serverId, password);
  }

  Future<void> _doConnect(
    String host,
    int port, [
    String? serverId,
    String? password,
  ]) async {
    _status = ConnectionStatus.connecting;
    _waitingAuth = false;
    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: SocketConfig.connectionTimeout,
      );
      LoggerService.info('TcpSocketClient TCP connected to $host:$port');

      _subscription = _socket!.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      final useAuth =
          serverId != null && serverId.isNotEmpty && password != null;
      if (useAuth) {
        _waitingAuth = true;
        final passwordHash = PasswordHasher.hash(password, serverId);
        final authRequest = createAuthRequest(
          serverId: serverId,
          passwordHash: passwordHash,
        );
        await send(authRequest);
      } else {
        _status = ConnectionStatus.connected;
        _reconnectAttempts = 0;
        _startHeartbeat();
      }
    } on SocketException catch (e) {
      _status = ConnectionStatus.error;
      LoggerService.warning('TcpSocketClient connect failed: ${e.message}');
      if (_reconnectEnabled &&
          _reconnectHost != null &&
          !_disconnectRequested) {
        _scheduleReconnect();
      } else {
        rethrow;
      }
    } on Object catch (e) {
      _status = ConnectionStatus.error;
      LoggerService.warning('TcpSocketClient connect failed: $e');
      if (_reconnectEnabled &&
          _reconnectHost != null &&
          !_disconnectRequested) {
        _scheduleReconnect();
      } else {
        rethrow;
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatManager = HeartbeatManager(
      sendHeartbeat: (m) {
        send(m).catchError((_) {});
      },
      onTimeout: () => _handleDisconnect(scheduleReconnect: true),
    );
    _heartbeatManager!.start();
    _heartbeatSubscription = _messageController.stream.listen((m) {
      if (isHeartbeatMessage(m)) _heartbeatManager?.onHeartbeatReceived();
    });
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
        if (_waitingAuth && isAuthResponseMessage(message)) {
          _waitingAuth = false;
          final success = message.payload['success'] == true;
          if (!success) {
            _status = ConnectionStatus.authenticationFailed;
            _messageController.add(message);
            Future.microtask(() => _handleDisconnect(scheduleReconnect: false));
            return;
          }
          _status = ConnectionStatus.connected;
          _reconnectAttempts = 0;
          _startHeartbeat();
        }
        _messageController.add(message);
      } on ProtocolException catch (e) {
        LoggerService.warning('TcpSocketClient parse error: ${e.message}');
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
    LoggerService.warning('TcpSocketClient error: $error', error, stackTrace);
    _status = ConnectionStatus.error;
  }

  void _onDone() {
    _status = ConnectionStatus.disconnected;
    LoggerService.info('TcpSocketClient disconnected');
    _handleDisconnect(scheduleReconnect: true);
  }

  @override
  Future<void> send(Message message) async {
    final canSend =
        _socket != null &&
        (_status == ConnectionStatus.connected ||
            _status == ConnectionStatus.connecting);
    if (!canSend) {
      throw StateError('TcpSocketClient not connected');
    }
    try {
      final data = _protocol.serializeMessage(message);
      _socket!.add(data);
      await _socket!.flush();
    } on Object catch (e) {
      LoggerService.warning('TcpSocketClient send error: $e');
      rethrow;
    }
  }

  void _scheduleReconnect() {
    if (_reconnectHost == null ||
        _reconnectPort == null ||
        _disconnectRequested ||
        _reconnectAttempts >= SocketConfig.maxReconnectAttempts) {
      if (_reconnectAttempts >= SocketConfig.maxReconnectAttempts) {
        LoggerService.warning(
          'TcpSocketClient max reconnect attempts reached',
        );
      }
      _reconnectHost = null;
      _reconnectPort = null;
      if (!_messageController.isClosed) {
        _messageController.close();
      }
      return;
    }

    final delaySeconds = math.pow(2, _reconnectAttempts).toInt();
    final delay = Duration(seconds: delaySeconds);
    LoggerService.info(
      'TcpSocketClient scheduling reconnect in ${delay.inSeconds}s',
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _attemptReconnect);
  }

  Future<void> _attemptReconnect() async {
    _reconnectTimer = null;
    final host = _reconnectHost;
    final port = _reconnectPort;
    if (host == null || port == null || _disconnectRequested) return;

    if (_reconnectAttempts >= SocketConfig.maxReconnectAttempts) {
      _reconnectHost = null;
      _reconnectPort = null;
      if (!_messageController.isClosed) {
        _messageController.close();
      }
      return;
    }

    _reconnectAttempts++;
    LoggerService.info(
      'TcpSocketClient reconnect attempt $_reconnectAttempts',
    );

    try {
      await _doConnect(
        host,
        port,
        _reconnectServerId,
        _reconnectPassword,
      );
    } on Object catch (_) {
      _scheduleReconnect();
    }
  }

  Future<void> _handleDisconnect({required bool scheduleReconnect}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _heartbeatSubscription?.cancel();
    _heartbeatSubscription = null;
    _heartbeatManager?.stop();
    _heartbeatManager = null;
    _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _status = ConnectionStatus.disconnected;

    if (scheduleReconnect && _reconnectEnabled && _reconnectHost != null) {
      _scheduleReconnect();
    } else {
      _reconnectHost = null;
      _reconnectPort = null;
      if (!_messageController.isClosed) {
        _messageController.close();
      }
    }
    LoggerService.info('TcpSocketClient disconnected');
  }

  @override
  Future<void> disconnect() async {
    _disconnectRequested = true;
    _reconnectEnabled = false;
    _reconnectHost = null;
    _reconnectPort = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _heartbeatSubscription?.cancel();
    _heartbeatSubscription = null;
    _heartbeatManager?.stop();
    _heartbeatManager = null;
    await _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _status = ConnectionStatus.disconnected;
    if (!_messageController.isClosed) {
      _messageController.close();
    }
    LoggerService.info('TcpSocketClient disconnected');
  }
}
