import 'package:backup_database/domain/entities/connection/connected_client.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';
import 'package:flutter/foundation.dart';

class ConnectedClientProvider extends ChangeNotifier {
  ConnectedClientProvider(this._server);

  final SocketServerService _server;

  List<ConnectedClient> _clients = [];
  bool _isLoading = false;
  String? _error;

  List<ConnectedClient> get clients => _clients;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isServerRunning => _server.isRunning;
  int get port => _server.port;

  Future<void> refresh() async {
    if (!_server.isRunning) {
      _clients = [];
      _error = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _clients = await _server.getConnectedClients();
      _isLoading = false;
      notifyListeners();
    } on Object catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> disconnectClient(String clientId) async {
    if (!_server.isRunning) return;

    _error = null;
    try {
      await _server.disconnectClient(clientId);
      await refresh();
    } on Object catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> startServer({int port = 9527}) async {
    if (_server.isRunning) return;

    _error = null;
    try {
      await _server.start(port: port);
      await refresh();
    } on Object catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> stopServer() async {
    if (!_server.isRunning) return;

    _error = null;
    try {
      await _server.stop();
      _clients = [];
      notifyListeners();
    } on Object catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
