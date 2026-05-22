import 'dart:async';

import 'package:backup_database/domain/entities/connection_status.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';

export 'package:backup_database/domain/entities/connection_status.dart';

abstract class SocketClientService {
  Future<void> connect({
    required String host,
    required int port,
    String? serverId,
    String? password,
  });
  Future<void> disconnect();
  bool get isConnected;
  ConnectionStatus get status;
  Stream<Message> get messageStream;
  Stream<ConnectionStatus> get statusStream;
  Future<void> send(Message message);
}
