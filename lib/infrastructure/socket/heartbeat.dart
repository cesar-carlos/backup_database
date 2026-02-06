import 'dart:async';
import 'dart:convert';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

Message createHeartbeatMessage() {
  final payload = <String, dynamic>{
    'ts': DateTime.now().millisecondsSinceEpoch,
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.heartbeat,
      length: length,
    ),
    payload: payload,
    checksum: 0,
  );
}

bool isHeartbeatMessage(Message message) =>
    message.header.type == MessageType.heartbeat;

class HeartbeatManager {
  HeartbeatManager({
    required void Function(Message) sendHeartbeat,
    required void Function() onTimeout,
    Duration? interval,
    Duration? timeout,
  }) : _sendHeartbeat = sendHeartbeat,
       _onTimeout = onTimeout,
       _interval = interval ?? SocketConfig.heartbeatInterval,
       _timeout = timeout ?? SocketConfig.heartbeatTimeout;

  final void Function(Message) _sendHeartbeat;
  final void Function() _onTimeout;
  final Duration _interval;
  final Duration _timeout;

  Timer? _sendTimer;
  Timer? _checkTimer;
  DateTime? _lastReceived;

  void start() {
    stop();
    _lastReceived = DateTime.now();
    _sendTimer = Timer.periodic(_interval, (_) {
      try {
        _sendHeartbeat(createHeartbeatMessage());
      } on Object catch (e) {
        LoggerService.warning('HeartbeatManager send error: $e');
      }
    });
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_lastReceived == null) return;
      if (DateTime.now().difference(_lastReceived!) > _timeout) {
        LoggerService.info('HeartbeatManager timeout');
        _onTimeout();
      }
    });
  }

  void onHeartbeatReceived() {
    _lastReceived = DateTime.now();
  }

  void stop() {
    _sendTimer?.cancel();
    _sendTimer = null;
    _checkTimer?.cancel();
    _checkTimer = null;
    _lastReceived = null;
  }
}
