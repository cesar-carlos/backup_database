import 'dart:async';

import 'package:backup_database/domain/entities/connection/connected_client.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';

abstract class SocketServerService {
  Future<void> start({int port = 9527});
  Future<void> stop();
  Future<void> restart();
  bool get isRunning;
  int get port;
  Stream<Message> get messageStream;
  Future<List<ConnectedClient>> getConnectedClients();
  Future<void> disconnectClient(String clientId);
  Future<void> broadcastToAll(Message message);
  Future<void> sendToClient(String clientId, Message message);
}
