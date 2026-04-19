import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/domain/entities/connection/connected_client.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';
import 'package:flutter/foundation.dart';

class ConnectedClientProvider extends ChangeNotifier with AsyncStateMixin {
  ConnectedClientProvider(this._server);

  final SocketServerService _server;

  List<ConnectedClient> _clients = [];

  List<ConnectedClient> get clients => _clients;
  bool get isServerRunning => _server.isRunning;
  int get port => _server.port;

  Future<void> refresh() async {
    if (!_server.isRunning) {
      _clients = const [];
      clearError();
      notifyListeners();
      return;
    }

    await runAsync<void>(
      action: () async {
        _clients = await _server.getConnectedClients();
      },
    );
  }

  Future<void> disconnectClient(String clientId) async {
    if (!_server.isRunning) return;
    final ok = await runAsync<bool>(
      action: () async {
        await _server.disconnectClient(clientId);
        return true;
      },
    );
    if (ok ?? false) await refresh();
  }

  Future<void> startServer({int port = 9527}) async {
    if (_server.isRunning) return;
    final ok = await runAsync<bool>(
      action: () async {
        await _server.start(port: port);
        return true;
      },
    );
    if (ok ?? false) await refresh();
  }

  Future<void> stopServer() async {
    if (!_server.isRunning) return;
    await runAsync<void>(
      action: () async {
        await _server.stop();
        _clients = const [];
      },
    );
  }
}
