import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/repositories/i_server_connection_repository.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/client/socket_client_service.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class ServerConnectionProvider extends ChangeNotifier {
  ServerConnectionProvider(
    this._repository,
    this._connectionManager,
  ) {
    loadConnections();
  }

  final IServerConnectionRepository _repository;
  final ConnectionManager _connectionManager;

  List<ServerConnection> _connections = [];
  bool _isLoading = false;
  String? _error;
  bool _isConnecting = false;
  bool _isTestingConnection = false;

  List<ServerConnection> get connections => _connections;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnecting => _isConnecting;
  bool get isTestingConnection => _isTestingConnection;
  bool get isConnected => _connectionManager.isConnected;
  ConnectionStatus get connectionStatus => _connectionManager.status;
  String? get activeHost => _connectionManager.activeHost;
  int? get activePort => _connectionManager.activePort;

  Future<void> loadConnections() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _repository.getAll();

    result.fold(
      (list) {
        _connections = list;
        _isLoading = false;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<bool> saveConnection({
    required String name,
    required String serverId,
    required String host,
    required int port,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final now = DateTime.now();
    final connection = ServerConnection(
      id: const Uuid().v4(),
      name: name,
      serverId: serverId,
      host: host,
      port: port,
      password: password,
      isOnline: false,
      createdAt: now,
      updatedAt: now,
    );

    final result = await _repository.save(connection);

    return result.fold(
      (saved) {
        _connections.add(saved);
        _isLoading = false;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> updateConnection(
    ServerConnection connection, {
    String? name,
    String? serverId,
    String? host,
    int? port,
    String? password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final updated = connection.copyWith(
      name: name ?? connection.name,
      serverId: serverId ?? connection.serverId,
      host: host ?? connection.host,
      port: port ?? connection.port,
      password: password ?? connection.password,
      updatedAt: DateTime.now(),
    );

    final result = await _repository.update(updated);

    return result.fold(
      (saved) {
        final index = _connections.indexWhere((c) => c.id == saved.id);
        if (index != -1) {
          _connections[index] = saved;
        }
        _isLoading = false;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> deleteConnection(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _repository.delete(id);

    return result.fold(
      (_) {
        _connections.removeWhere((c) => c.id == id);
        _isLoading = false;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<void> connectTo(String connectionId, {bool enableAutoReconnect = false}) async {
    _isConnecting = true;
    _error = null;
    notifyListeners();

    try {
      await _connectionManager.connectToSavedConnection(
        connectionId,
        enableAutoReconnect: enableAutoReconnect,
      );
    } on Object catch (e) {
      _error = e is StateError ? e.message : e.toString();
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _connectionManager.disconnect();
    notifyListeners();
  }

  Future<bool> testConnection(ServerConnection connection) async {
    _isTestingConnection = true;
    _error = null;
    notifyListeners();

    try {
      await _connectionManager.connect(
        host: connection.host,
        port: connection.port,
        serverId: connection.serverId,
        password: connection.password,
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final ok = _connectionManager.isConnected;
      await _connectionManager.disconnect();
      return ok;
    } on Object catch (e) {
      _error = e.toString();
      await _connectionManager.disconnect();
      return false;
    } finally {
      _isTestingConnection = false;
      notifyListeners();
    }
  }
}
