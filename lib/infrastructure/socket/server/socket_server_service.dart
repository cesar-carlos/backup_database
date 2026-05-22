import 'dart:async';

import 'package:backup_database/domain/entities/connection/connected_client.dart';
import 'package:backup_database/domain/services/i_socket_server_lifecycle.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';

abstract class SocketServerService implements ISocketServerLifecycle {
  @override
  @override
  Future<void> start({int port = 9527});
  Future<void> stop();
  Future<void> restart();
  @override
  bool get isRunning;
  @override
  int get port;
  Stream<Message> get messageStream;
  Future<List<ConnectedClient>> getConnectedClients();
  Future<void> disconnectClient(String clientId);
  Future<void> broadcastToAll(Message message);
  Future<void> sendToClient(String clientId, Message message);
}
