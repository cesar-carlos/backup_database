import 'dart:async';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/logging.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/remote_file_entry.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/repositories/i_server_connection_repository.dart';
import 'package:backup_database/infrastructure/protocol/capabilities_messages.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/diagnostics_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/execution_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/health_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/protocol/queue_events.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/protocol/session_messages.dart';
import 'package:backup_database/infrastructure/socket/client/client_rpc_transport.dart';
import 'package:backup_database/infrastructure/socket/client/file_transfer_resume_metadata_store.dart';
import 'package:backup_database/infrastructure/socket/client/remote_backup_stream_client.dart';
import 'package:backup_database/infrastructure/socket/client/remote_backup_types.dart';
import 'package:backup_database/infrastructure/socket/client/remote_database_config_rpc.dart';
import 'package:backup_database/infrastructure/socket/client/remote_diagnostics_rpc.dart';
import 'package:backup_database/infrastructure/socket/client/remote_file_transfer_client.dart';
import 'package:backup_database/infrastructure/socket/client/remote_schedule_rpc.dart';
import 'package:backup_database/infrastructure/socket/client/remote_session_rpc.dart';
import 'package:backup_database/infrastructure/socket/client/socket_client_service.dart';
import 'package:backup_database/infrastructure/socket/client/tcp_socket_client.dart';
import 'package:result_dart/result_dart.dart' as rd;

export 'package:backup_database/infrastructure/socket/client/remote_backup_types.dart';

class ConnectionManager {
  ConnectionManager({
    this._serverConnectionRepository,
    FileTransferResumeMetadataStore? resumeMetadataStore,
    Duration? fileTransferIdleTimeout,
  }) : _fileTransferIdleTimeout =
           fileTransferIdleTimeout ?? SocketConfig.fileTransferIdleTimeout,
       _socketLogger = di.getIt<SocketLoggerService>() {
    _rpc = ClientRpcTransport();
    _fileTransfer = RemoteFileTransferClient(
      rpc: _rpc,
      isConnected: () => isConnected,
      send: send,
      isResumeSupported: () => isResumeSupported,
      resumeMetadataStore:
          resumeMetadataStore ?? const FileTransferResumeMetadataStore(),
      idleTimeout: _fileTransferIdleTimeout,
    );
    _sessionRpc = RemoteSessionRpc(
      rpc: _rpc,
      isConnected: () => isConnected,
      send: send,
    );
    _scheduleRpc = RemoteScheduleRpc(
      rpc: _rpc,
      isConnected: () => isConnected,
      send: send,
    );
    _databaseConfigRpc = RemoteDatabaseConfigRpc(
      rpc: _rpc,
      isConnected: () => isConnected,
      send: send,
    );
    _diagnosticsRpc = RemoteDiagnosticsRpc(
      rpc: _rpc,
      isConnected: () => isConnected,
      send: send,
    );
    _backupStream = RemoteBackupStreamClient(
      rpc: _rpc,
      isConnected: () => isConnected,
      send: send,
      sessionRpc: _sessionRpc,
      diagnosticsRpc: _diagnosticsRpc,
    );
  }

  final IServerConnectionRepository? _serverConnectionRepository;
  final Duration _fileTransferIdleTimeout;
  final SocketLoggerService _socketLogger;
  late final ClientRpcTransport _rpc;
  late final RemoteFileTransferClient _fileTransfer;
  late final RemoteBackupStreamClient _backupStream;
  late final RemoteSessionRpc _sessionRpc;
  late final RemoteScheduleRpc _scheduleRpc;
  late final RemoteDatabaseConfigRpc _databaseConfigRpc;
  late final RemoteDiagnosticsRpc _diagnosticsRpc;

  TcpSocketClient? _client;
  String? _activeHost;
  int? _activePort;
  // ignore: cancel_subscriptions -- cancelado em [disconnect].
  StreamSubscription<Message>? _messageSubscription;
  // ignore: cancel_subscriptions -- cancelado em [disconnect].
  StreamSubscription<ConnectionStatus>? _statusSubscription;

  final StreamController<QueueEvent> _queueEventController =
      StreamController<QueueEvent>.broadcast();

  ServerCapabilities? _cachedServerCapabilities;

  bool get hasActiveTransfers => _fileTransfer.hasActiveTransfers;

  TcpSocketClient? get activeClient => _client;
  String? get activeHost => _activeHost;
  int? get activePort => _activePort;
  bool get isConnected => _client?.isConnected ?? false;
  ConnectionStatus get status =>
      _client?.status ?? ConnectionStatus.disconnected;
  String? get lastErrorMessage => _client?.lastErrorMessage;
  ErrorCode? get lastErrorCode => _client?.lastErrorCode;
  Stream<Message>? get messageStream => _client?.messageStream;
  Stream<ConnectionStatus>? get statusStream => _client?.statusStream;

  ServerCapabilities? get serverCapabilities => _cachedServerCapabilities;

  ServerCapabilities get _effectiveCapabilities =>
      _cachedServerCapabilities ?? ServerCapabilities.legacyDefault;

  bool get isRunIdSupported => _effectiveCapabilities.supportsRunId;
  bool get isExecutionQueueSupported =>
      _effectiveCapabilities.supportsExecutionQueue;
  bool get isResumeSupported => _effectiveCapabilities.supportsResume;
  Stream<QueueEvent> get queueEvents => _queueEventController.stream;
  bool get isArtifactRetentionSupported =>
      _effectiveCapabilities.supportsArtifactRetention;
  bool get isChunkAckSupported => _effectiveCapabilities.supportsChunkAck;
  bool get isFirebirdSupported => _effectiveCapabilities.supportsFirebird;
  bool get isAsyncStartSupported => _effectiveCapabilities.supportsAsyncStart;

  Future<void> connect({
    required String host,
    required int port,
    String? serverId,
    String? password,
    bool enableAutoReconnect = false,
    bool refreshCapabilitiesOnConnect = true,
  }) async {
    await disconnect();
    _client = TcpSocketClient(
      socketLogger: _socketLogger,
      canDisconnectOnTimeout: () => !hasActiveTransfers,
    );
    await _client!.connect(
      host: host,
      port: port,
      serverId: serverId,
      password: password,
      enableAutoReconnect: enableAutoReconnect,
    );
    _activeHost = host;
    _activePort = port;
    _messageSubscription = _client!.messageStream.listen(_onMessage);
    _statusSubscription = _client!.statusStream.listen(_onStatusChanged);
    final useAuth =
        serverId != null &&
        serverId.isNotEmpty &&
        password != null &&
        password.isNotEmpty;
    try {
      await _awaitConnectionReady(useAuth: useAuth);
    } on Object {
      await disconnect();
      rethrow;
    }

    if (refreshCapabilitiesOnConnect) {
      try {
        await refreshServerCapabilities();
      } on Object catch (e) {
        LoggerService.warning(
          '[ConnectionManager] Refresh automatico de capabilities falhou: $e. '
          'Cache permanece ${_cachedServerCapabilities == null ? "vazio" : "populado"}.',
        );
      }
    }
  }

  Future<void> _awaitConnectionReady({required bool useAuth}) async {
    final client = _client;
    if (client == null) {
      throw StateError('ConnectionManager not connected');
    }

    if (!useAuth) {
      if (!client.isConnected) {
        throw StateError(
          client.lastErrorMessage ?? 'Não foi possível conectar ao servidor',
        );
      }
      return;
    }

    final deadline = DateTime.now().add(SocketConfig.connectionTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final currentStatus = client.status;
      if (currentStatus == ConnectionStatus.connected) {
        return;
      }

      if (currentStatus == ConnectionStatus.authenticationFailed) {
        throw StateError(
          client.lastErrorMessage ?? 'Autenticação rejeitada pelo servidor',
        );
      }

      if (currentStatus == ConnectionStatus.error) {
        throw StateError(
          client.lastErrorMessage ?? 'Erro ao conectar no servidor',
        );
      }

      if (currentStatus == ConnectionStatus.disconnected) {
        throw StateError(
          client.lastErrorMessage ??
              'Conexão encerrada pelo servidor durante autenticação',
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    throw TimeoutException(
      'Tempo esgotado aguardando resposta de autenticação do servidor',
    );
  }

  void _onStatusChanged(ConnectionStatus status) {
    final isTerminal =
        status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error ||
        status == ConnectionStatus.authenticationFailed;
    if (!isTerminal) return;
    if (_rpc.isEmpty &&
        !_backupStream.hasActiveBackups &&
        !_fileTransfer.hasActiveTransfers) {
      return;
    }
    LoggerService.warning(
      '[ConnectionManager] Conexão entrou em estado $status com '
      '${_rpc.pendingCount} request(s), '
      '${_fileTransfer.activeCount} transferência(s) e '
      '${_backupStream.activeCount} backup(s) pendente(s) — abortando.',
    );
    _abortPending(status);
  }

  void _abortPending(ConnectionStatus status) {
    final stateError = StateError(
      'Conexão encerrada (status: $status) com operações pendentes',
    );
    final exception = Exception(stateError.message);
    _rpc.abortAll(stateError);
    _backupStream.abortAll(exception);
    unawaited(_fileTransfer.abortAll(exception, closeSinks: false));
  }

  void _onMessage(Message message) {
    final requestId = message.header.requestId;
    final transferState = _fileTransfer.transferFor(requestId);
    if (transferState != null) {
      unawaited(
        _fileTransfer.handleMessage(requestId, message, transferState),
      );
      return;
    }
    final queueEvent = readQueueEvent(message);
    if (queueEvent != null) {
      if (_backupStream.shouldAcceptQueueEvent(
        eventId: queueEvent.eventId,
        sequence: queueEvent.sequence,
        runId: queueEvent.runId,
      )) {
        _backupStream.handleQueueEvent(queueEvent);
        _queueEventController.add(queueEvent);
      } else {
        LoggerService.debug(
          '[ConnectionManager] evento de fila duplicado ignorado: '
          '${queueEvent.type.name} runId=${queueEvent.runId}',
        );
      }
      return;
    }
    if (isBackupStreamMessage(message.header.type)) {
      final messageRunId = getRunIdFromBackupMessage(message);
      if (messageRunId != null && messageRunId.isNotEmpty) {
        final byRunId = _backupStream.backupForRunId(messageRunId);
        if (byRunId != null) {
          _backupStream.handleBackupProgressMessage(message, byRunId);
          return;
        }
        _backupStream.bufferUntilListener(
          runId: messageRunId,
          message: message,
        );
        return;
      }
      final backupState = _backupStream.backupForRequestId(requestId);
      if (backupState != null) {
        _backupStream.handleBackupProgressMessage(message, backupState);
        return;
      }
      return;
    }
    _rpc.completeIfPending(requestId, message);
  }

  Future<void> disconnect() async {
    final messageSub = _messageSubscription;
    _messageSubscription = null;
    await messageSub?.cancel();
    final statusSub = _statusSubscription;
    _statusSubscription = null;
    await statusSub?.cancel();

    await _fileTransfer.abortAll(
      Exception('Disconnected during file transfer'),
      closeSinks: true,
    );
    _backupStream.abortAll(Exception('Disconnected during backup'));
    _rpc.completeAllDisconnected();
    _cachedServerCapabilities = null;
    if (_client != null) {
      await _client!.disconnect();
      _client = null;
      _activeHost = null;
      _activePort = null;
    }
  }

  Future<rd.Result<List<Schedule>>> listSchedules() {
    return _scheduleRpc.listSchedules();
  }

  Future<rd.Result<Schedule>> updateSchedule(Schedule schedule) {
    return _scheduleRpc.updateSchedule(schedule);
  }

  Future<rd.Result<List<RemoteFileEntry>>> listAvailableFiles() {
    return _fileTransfer.listAvailableFiles();
  }

  Future<rd.Result<void>> requestFile({
    required String filePath,
    required String outputPath,
    String? scheduleId,
    String? runId,
    void Function(int currentChunk, int totalChunks)? onProgress,
  }) {
    return _fileTransfer.requestFile(
      filePath: filePath,
      outputPath: outputPath,
      scheduleId: scheduleId,
      runId: runId,
      onProgress: onProgress,
    );
  }

  @Deprecated(
    'Use executeRemoteBackup para aceite imediato + acompanhamento por runId. '
    'Sera removido em PR futuro apos 2 releases com este aviso.',
  )
  Future<rd.Result<String>> executeSchedule(
    String scheduleId, {
    BackupProgressCallback? onProgress,
  }) {
    return _backupStream.executeSchedule(
      scheduleId,
      onProgress: onProgress,
    );
  }

  Future<rd.Result<ServerCapabilities>> refreshServerCapabilities() async {
    final result = await _sessionRpc.getServerCapabilities();
    final caps = result.fold(
      (s) => s,
      (failure) {
        LoggerService.info(
          '[ConnectionManager] getServerCapabilities falhou '
          '(servidor v1 legado ou erro): $failure. '
          'Usando ServerCapabilities.legacyDefault como fallback.',
        );
        return ServerCapabilities.legacyDefault;
      },
    );
    _cachedServerCapabilities = caps;
    return rd.Success(caps);
  }

  Future<rd.Result<ServerCapabilities>> getServerCapabilities() {
    return _sessionRpc.getServerCapabilities();
  }

  Future<rd.Result<ServerHealth>> getServerHealth() {
    return _sessionRpc.getServerHealth();
  }

  Future<rd.Result<ServerSession>> getServerSession() {
    return _sessionRpc.getServerSession();
  }

  Future<rd.Result<PreflightResult>> validateServerBackupPrerequisites() {
    return _sessionRpc.validateServerBackupPrerequisites();
  }

  Future<rd.Result<ExecutionStatusResult>> getExecutionStatus(String runId) {
    return _sessionRpc.getExecutionStatus(runId);
  }

  Future<rd.Result<ExecutionQueueResult>> getExecutionQueue() {
    return _sessionRpc.getExecutionQueue();
  }

  Future<rd.Result<TestDatabaseConnectionResult>> testRemoteDatabaseConnection({
    required RemoteDatabaseType databaseType,
    String? databaseConfigId,
    Map<String, dynamic>? config,
    Duration? timeout,
  }) {
    return _sessionRpc.testRemoteDatabaseConnection(
      databaseType: databaseType,
      databaseConfigId: databaseConfigId,
      config: config,
      timeout: timeout,
    );
  }

  Future<rd.Result<StartBackupResult>> startRemoteBackup({
    required String scheduleId,
    String? idempotencyKey,
    bool queueIfBusy = false,
  }) {
    return _sessionRpc.startRemoteBackup(
      scheduleId: scheduleId,
      idempotencyKey: idempotencyKey,
      queueIfBusy: queueIfBusy,
    );
  }

  Future<rd.Result<String>> executeRemoteBackup({
    required String scheduleId,
    String? idempotencyKey,
    bool queueIfBusy = true,
    BackupProgressCallback? onProgress,
    void Function(String runId)? onRunIdKnown,
  }) {
    return _backupStream.executeRemoteBackup(
      scheduleId: scheduleId,
      idempotencyKey: idempotencyKey,
      queueIfBusy: queueIfBusy,
      onProgress: onProgress,
      onRunIdKnown: onRunIdKnown,
    );
  }

  void attachRemoteBackupListener({
    required String runId,
    required BackupProgressCallback? onProgress,
  }) {
    _backupStream.attachListener(runId: runId, onProgress: onProgress);
  }

  Future<rd.Result<String>> waitForRemoteBackupCompletion(String runId) {
    return _backupStream.waitForCompletion(runId);
  }

  Future<rd.Result<CancelBackupResult>> cancelRemoteBackup({
    String? runId,
    String? scheduleId,
    String? idempotencyKey,
  }) {
    return _sessionRpc.cancelRemoteBackup(
      runId: runId,
      scheduleId: scheduleId,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<rd.Result<ScheduleMutationResult>> createRemoteSchedule({
    required Schedule schedule,
    String? idempotencyKey,
  }) {
    return _scheduleRpc.createRemoteSchedule(
      schedule: schedule,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<rd.Result<ScheduleMutationResult>> deleteRemoteSchedule({
    required String scheduleId,
    String? idempotencyKey,
  }) {
    return _scheduleRpc.deleteRemoteSchedule(
      scheduleId: scheduleId,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<rd.Result<ScheduleMutationResult>> pauseRemoteSchedule({
    required String scheduleId,
    String? idempotencyKey,
  }) {
    return _scheduleRpc.pauseRemoteSchedule(
      scheduleId: scheduleId,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<rd.Result<ScheduleMutationResult>> resumeRemoteSchedule({
    required String scheduleId,
    String? idempotencyKey,
  }) {
    return _scheduleRpc.resumeRemoteSchedule(
      scheduleId: scheduleId,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<rd.Result<DatabaseConfigListResult>> listRemoteDatabaseConfigs(
    RemoteDatabaseType databaseType,
  ) {
    return _databaseConfigRpc.listRemoteDatabaseConfigs(databaseType);
  }

  Future<rd.Result<DatabaseConfigMutationResult>> createRemoteDatabaseConfig({
    required RemoteDatabaseType databaseType,
    required Map<String, dynamic> config,
    String? idempotencyKey,
  }) {
    return _databaseConfigRpc.createRemoteDatabaseConfig(
      databaseType: databaseType,
      config: config,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<rd.Result<DatabaseConfigMutationResult>> updateRemoteDatabaseConfig({
    required RemoteDatabaseType databaseType,
    required Map<String, dynamic> config,
    String? idempotencyKey,
  }) {
    return _databaseConfigRpc.updateRemoteDatabaseConfig(
      databaseType: databaseType,
      config: config,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<rd.Result<DatabaseConfigMutationResult>> deleteRemoteDatabaseConfig({
    required RemoteDatabaseType databaseType,
    required String configId,
    String? idempotencyKey,
  }) {
    return _databaseConfigRpc.deleteRemoteDatabaseConfig(
      databaseType: databaseType,
      configId: configId,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<rd.Result<CancelQueuedBackupResult>> cancelQueuedRemoteBackup({
    required String runId,
    String? idempotencyKey,
  }) {
    return _sessionRpc.cancelQueuedRemoteBackup(
      runId: runId,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<rd.Result<RunLogsResult>> getRunLogs({
    required String runId,
    int? maxLines,
  }) {
    return _diagnosticsRpc.getRunLogs(runId: runId, maxLines: maxLines);
  }

  Future<rd.Result<RunErrorDetailsResult>> getRunErrorDetails({
    required String runId,
  }) {
    return _diagnosticsRpc.getRunErrorDetails(runId: runId);
  }

  Future<rd.Result<ArtifactMetadataResult>> getArtifactMetadata({
    required String runId,
  }) {
    return _diagnosticsRpc.getArtifactMetadata(runId: runId);
  }

  Future<rd.Result<CleanupStagingResult>> cleanupRemoteStaging({
    required String runId,
    String? idempotencyKey,
  }) {
    return _diagnosticsRpc.cleanupRemoteStaging(
      runId: runId,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<rd.Result<Map<String, dynamic>>> getServerMetrics() {
    return _diagnosticsRpc.getServerMetrics();
  }

  Future<rd.Result<void>> cancelSchedule(String scheduleId) {
    return _scheduleRpc.cancelSchedule(scheduleId);
  }

  Future<void> send(Message message) async {
    final client = _client;
    if (client == null || !client.isConnected) {
      throw StateError('ConnectionManager not connected');
    }
    await client.send(message);
  }

  Future<List<ServerConnection>> getSavedConnections() async {
    final repo = _serverConnectionRepository;
    if (repo == null) {
      return const <ServerConnection>[];
    }
    final result = await repo.getAll();
    return result.fold(
      (list) => list,
      (failure) {
        LoggerService.warning(
          'Falha ao listar conexões salvas: $failure',
        );
        return const <ServerConnection>[];
      },
    );
  }

  Future<void> connectToSavedConnection(
    String connectionId, {
    bool enableAutoReconnect = false,
  }) async {
    final repo = _serverConnectionRepository;
    if (repo == null) {
      throw StateError(
        'ConnectionManager has no IServerConnectionRepository; '
        'cannot connect to saved connection',
      );
    }
    final result = await repo.getById(connectionId);
    final connection = result.fold(
      (found) => found,
      (failure) => throw StateError(
        'Saved connection not found: $connectionId ($failure)',
      ),
    );
    await connect(
      host: connection.host,
      port: connection.port,
      serverId: connection.serverId,
      password: connection.password,
      enableAutoReconnect: enableAutoReconnect,
    );
  }
}
