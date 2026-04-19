import 'dart:async';

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/repositories/i_connection_log_repository.dart';
import 'package:backup_database/domain/repositories/i_server_connection_repository.dart';
import 'package:backup_database/infrastructure/protocol/capabilities_messages.dart';
import 'package:backup_database/infrastructure/protocol/health_messages.dart';
import 'package:backup_database/infrastructure/protocol/session_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/client/socket_client_service.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class ServerConnectionProvider extends ChangeNotifier with AsyncStateMixin {
  ServerConnectionProvider(
    this._repository,
    this._connectionManager,
    this._connectionLogRepository,
  ) {
    loadConnections();
    _listenToConnectionStatus();
  }

  final IServerConnectionRepository _repository;
  final ConnectionManager _connectionManager;
  final IConnectionLogRepository _connectionLogRepository;
  StreamSubscription<ConnectionStatus>? _statusSubscription;

  List<ServerConnection> _connections = [];
  bool _isConnecting = false;
  bool _isTestingConnection = false;
  bool _hasTriedAutoConnectAtStartup = false;

  /// Cache local de saude/sessao do servidor conectado (M1.10 / M4.1).
  ///
  /// `null` enquanto nao ha conexao ou enquanto `refreshServerStatus`
  /// ainda nao foi chamado. Capabilities ja vive no `ConnectionManager`
  /// e e exposto via passa-through para evitar duplicacao.
  ///
  /// Invalidado em `disconnect` para impedir UI de exibir status stale
  /// apos cair a conexao ou trocar de servidor.
  ServerHealth? _serverHealth;
  ServerSession? _serverSession;
  bool _isRefreshingStatus = false;

  void _listenToConnectionStatus() {
    _statusSubscription?.cancel();
    _statusSubscription = _connectionManager.statusStream?.listen((status) {
      // Quando a conexao cai externamente (timeout, RST, erro), invalida
      // cache de health/session — UI nao deve continuar mostrando dados
      // de servidor que ja saiu. Capabilities tambem foi limpo no
      // disconnect interno do ConnectionManager.
      final isTerminal = status == ConnectionStatus.disconnected ||
          status == ConnectionStatus.error ||
          status == ConnectionStatus.authenticationFailed;
      if (isTerminal) {
        _resetServerStatusCache();
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  List<ServerConnection> get connections => _connections;
  bool get isConnecting => _isConnecting;
  bool get isTestingConnection => _isTestingConnection;
  bool get isConnected => _connectionManager.isConnected;
  ConnectionStatus get connectionStatus => _connectionManager.status;
  String? get activeHost => _connectionManager.activeHost;
  int? get activePort => _connectionManager.activePort;

  /// Capabilities do servidor conectado (passa-through do
  /// `ConnectionManager` que ja faz cache + invalidacao).
  /// `null` quando desconectado ou antes do auto-refresh do
  /// `connect()` completar.
  ServerCapabilities? get serverCapabilities =>
      _connectionManager.serverCapabilities;

  /// Saude do servidor conectado, conforme ultimo `refreshServerStatus`.
  /// Use [isServerHealthy] para gate sincrono em UI/disparo de backup.
  ServerHealth? get serverHealth => _serverHealth;

  /// Sessao do cliente conforme percebida pelo servidor, conforme
  /// ultimo `refreshServerStatus`.
  ServerSession? get serverSession => _serverSession;

  /// `true` enquanto `refreshServerStatus` esta em andamento. UI pode
  /// usar para mostrar loading no painel de status do servidor.
  bool get isRefreshingStatus => _isRefreshingStatus;

  /// Atalho que o codigo de UI/backup usa para decidir se opera. Cai
  /// em `false` quando saude e desconhecida (defesa: melhor bloquear
  /// e pedir refresh do que disparar backup contra servidor instavel).
  bool get isServerHealthy => _serverHealth?.isOk ?? false;

  // Atalhos para os getters de feature do ConnectionManager — UI nao
  // precisa importar capabilities_messages.dart.
  bool get isRunIdSupported => _connectionManager.isRunIdSupported;
  bool get isExecutionQueueSupported =>
      _connectionManager.isExecutionQueueSupported;
  bool get isArtifactRetentionSupported =>
      _connectionManager.isArtifactRetentionSupported;
  bool get isChunkAckSupported => _connectionManager.isChunkAckSupported;

  Future<void> loadConnections() async {
    await runAsync<void>(
      action: () async {
        final result = await _repository.getAll();
        result.fold(
          (list) {
            _connections = list;
            if (currentAppMode == AppMode.client &&
                !_hasTriedAutoConnectAtStartup &&
                list.isNotEmpty &&
                !_connectionManager.isConnected) {
              _hasTriedAutoConnectAtStartup = true;
              unawaited(tryConnectToSavedServersInBackground());
            }
          },
          (failure) => throw failure,
        );
      },
    );
  }

  /// Tenta conectar em sequência a todos os servidores configurados em background.
  /// Para na primeira conexão bem-sucedida. Não altera [isConnecting].
  Future<void> tryConnectToSavedServersInBackground() async {
    if (currentAppMode != AppMode.client) return;
    if (_connectionManager.isConnected) return;
    final list = _connections;
    if (list.isEmpty) return;

    for (final connection in list) {
      try {
        await _connectionManager.connectToSavedConnection(
          connection.id,
          enableAutoReconnect: true,
        );
        if (_connectionManager.isConnected) {
          await _logConnectionAttempt(
            clientHost: connection.name,
            serverId: connection.serverId,
            success: true,
          );
          LoggerService.info(
            'Conectado ao servidor ${connection.name} (${connection.host}:${connection.port}) em background',
          );
          // Popula cache de health/session imediatamente apos conexao.
          // Capabilities ja vem populada pelo auto-refresh do connect().
          unawaited(refreshServerStatus());
          notifyListeners();
          return;
        }
        // Connect retornou sem throw mas também sem estabelecer a conexão
        // (ex.: handshake rejeitado). Antes esse caso passava silencioso e
        // não gerava entrada no histórico; agora registramos a tentativa.
        final silentError =
            _connectionManager.lastErrorMessage ?? 'Conexão não estabelecida';
        await _logConnectionAttempt(
          clientHost: connection.name,
          serverId: connection.serverId,
          success: false,
          errorMessage: silentError,
        );
        LoggerService.debug(
          'Conexão silenciosa a ${connection.name} em background falhou: $silentError',
        );
      } on Object catch (e) {
        final errorMessage = e is StateError ? e.message : e.toString();
        await _logConnectionAttempt(
          clientHost: connection.name,
          serverId: connection.serverId,
          success: false,
          errorMessage: errorMessage,
        );
        LoggerService.debug(
          'Falha ao conectar a ${connection.name} em background: $e',
        );
        await _connectionManager.disconnect();
      }
    }
    notifyListeners();
  }

  Future<void> _logConnectionAttempt({
    required String clientHost,
    required bool success,
    String? serverId,
    String? errorMessage,
  }) async {
    final result = await _connectionLogRepository.insertAttempt(
      clientHost: clientHost,
      success: success,
      serverId: serverId,
      errorMessage: errorMessage,
    );
    result.fold((_) {}, (_) {});
  }

  Future<bool> saveConnection({
    required String name,
    required String serverId,
    required String host,
    required int port,
    required String password,
  }) async {
    final ok = await runAsync<bool>(
      action: () async {
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
            _connections = [..._connections, saved];
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    return ok ?? false;
  }

  Future<bool> updateConnection(
    ServerConnection connection, {
    String? name,
    String? serverId,
    String? host,
    int? port,
    String? password,
  }) async {
    final ok = await runAsync<bool>(
      action: () async {
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
            _connections = [
              for (final c in _connections)
                if (c.id == saved.id) saved else c,
            ];
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    return ok ?? false;
  }

  Future<bool> deleteConnection(String id) async {
    final ok = await runAsync<bool>(
      action: () async {
        final result = await _repository.delete(id);
        return result.fold(
          (_) {
            _connections = _connections.where((c) => c.id != id).toList();
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    return ok ?? false;
  }

  Future<void> connectTo(
    String connectionId, {
    bool enableAutoReconnect = false,
  }) async {
    _isConnecting = true;
    notifyListeners();

    LoggerService.info('Tentando conectar à conexão: $connectionId');

    final index = _connections.indexWhere((c) => c.id == connectionId);
    final connection = index >= 0 ? _connections[index] : null;

    try {
      await runAsync<void>(
        action: () async {
          await _connectionManager.connectToSavedConnection(
            connectionId,
            enableAutoReconnect: enableAutoReconnect,
          );
          if (_connectionManager.isConnected && connection != null) {
            await _logConnectionAttempt(
              clientHost: connection.name,
              serverId: connection.serverId,
              success: true,
            );
            // Popula health/session imediatamente apos conexao bem-
            // sucedida. UI pode mostrar status assim que abrir.
            unawaited(refreshServerStatus());
          }
          LoggerService.info('Conexão estabelecida com sucesso');
        },
      );
      if (error != null && connection != null) {
        await _logConnectionAttempt(
          clientHost: connection.name,
          serverId: connection.serverId,
          success: false,
          errorMessage: error,
        );
        LoggerService.error('Erro ao conectar: $error');
      }
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _connectionManager.disconnect();
    _resetServerStatusCache();
    notifyListeners();
  }

  /// Consulta `getServerHealth` e `getServerSession` em paralelo e
  /// cacheia os snapshots para uso sincrono pela UI. Falhas de health
  /// ou session sao logadas mas nao propagam excecao — providers nunca
  /// devem quebrar UI por causa de status auxiliar.
  ///
  /// Notifica listeners no inicio (loading) e no fim (resultado).
  /// Idempotente: chamadas concorrentes durante refresh em curso
  /// retornam imediatamente.
  Future<void> refreshServerStatus() async {
    if (_isRefreshingStatus) return;
    if (!_connectionManager.isConnected) {
      // Sem conexao nao ha o que consultar. Garante cache limpo.
      _resetServerStatusCache();
      notifyListeners();
      return;
    }

    _isRefreshingStatus = true;
    notifyListeners();

    try {
      final results = await Future.wait<Object?>([
        _connectionManager.getServerHealth().then(
              (r) => r.fold<ServerHealth?>(
                (h) => h,
                (failure) {
                  LoggerService.info(
                    '[ServerConnectionProvider] getServerHealth falhou: '
                    '$failure. Health permanece com cache anterior.',
                  );
                  return null;
                },
              ),
            ),
        _connectionManager.getServerSession().then(
              (r) => r.fold<ServerSession?>(
                (s) => s,
                (failure) {
                  LoggerService.info(
                    '[ServerConnectionProvider] getServerSession falhou: '
                    '$failure. Session permanece com cache anterior.',
                  );
                  return null;
                },
              ),
            ),
      ]);

      final newHealth = results[0] as ServerHealth?;
      final newSession = results[1] as ServerSession?;

      // Apenas substitui cache quando refresh foi bem-sucedido —
      // preserva ultimo valor conhecido em caso de falha pontual
      // (servidor temporariamente indisponivel).
      if (newHealth != null) _serverHealth = newHealth;
      if (newSession != null) _serverSession = newSession;
    } finally {
      _isRefreshingStatus = false;
      notifyListeners();
    }
  }

  /// Limpa cache local de health/session. Chamado em `disconnect`
  /// e sempre que detectamos troca de servidor.
  void _resetServerStatusCache() {
    _serverHealth = null;
    _serverSession = null;
  }

  Future<bool> testConnection(ServerConnection connection) async {
    _isTestingConnection = true;
    notifyListeners();

    try {
      final ok = await runAsync<bool>(
        action: () async {
          await _connectionManager.connect(
            host: connection.host,
            port: connection.port,
            serverId: connection.serverId,
            password: connection.password,
          );
          await Future<void>.delayed(const Duration(milliseconds: 800));
          final connected = _connectionManager.isConnected;
          await _connectionManager.disconnect();
          if (!connected) {
            throw Exception(
              _connectionManager.lastErrorMessage ??
                  'Falha ao conectar no servidor',
            );
          }
          return true;
        },
      );
      if (!(ok ?? false)) {
        await _connectionManager.disconnect();
      }
      return ok ?? false;
    } finally {
      _isTestingConnection = false;
      notifyListeners();
    }
  }
}
