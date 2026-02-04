import 'package:backup_database/domain/entities/connection/connected_client.dart';
import 'package:backup_database/infrastructure/socket/server/client_handler.dart';

class ClientManager {
  ClientManager();

  final Map<String, ClientHandler> _handlers = {};
  final Map<String, DateTime> _connectedAt = {};

  void register(ClientHandler handler, DateTime connectedAt) {
    final clientId = handler.clientId;
    _handlers[clientId] = handler;
    _connectedAt[clientId] = connectedAt;
  }

  void unregister(String clientId) {
    _handlers.remove(clientId);
    _connectedAt.remove(clientId);
  }

  List<ClientHandler> getHandlers() => _handlers.values.toList();

  ClientHandler? getHandler(String clientId) => _handlers[clientId];

  Future<List<ConnectedClient>> getConnectedClients() async {
    final clients = <ConnectedClient>[];
    for (final entry in _handlers.entries) {
      final connectedAt = _connectedAt[entry.key] ?? DateTime.now();
      clients.add(entry.value.toConnectedClient(connectedAt));
    }
    return clients;
  }

  Future<void> disconnectClient(String clientId) async {
    final handler = _handlers[clientId];
    if (handler != null) {
      handler.disconnect();
    }
  }

  void disconnectAll() {
    final list = _handlers.values.toList();
    for (final handler in list) {
      handler.disconnect();
    }
    clear();
  }

  void clear() {
    _handlers.clear();
    _connectedAt.clear();
  }
}
