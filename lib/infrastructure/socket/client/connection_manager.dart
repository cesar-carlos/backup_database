import 'dart:async';

import 'package:backup_database/domain/entities/remote_file_entry.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/datasources/daos/server_connection_dao.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/protocol/file_chunker.dart';
import 'package:backup_database/infrastructure/protocol/file_transfer_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/metrics_messages.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/client/socket_client_service.dart';
import 'package:backup_database/infrastructure/socket/client/tcp_socket_client.dart';
import 'package:result_dart/result_dart.dart' as rd;

typedef BackupProgressCallback = void Function(
  String step,
  String message,
  double progress,
);

class ConnectionManager {
  ConnectionManager({ServerConnectionDao? serverConnectionDao})
    : _serverConnectionDao = serverConnectionDao;

  final ServerConnectionDao? _serverConnectionDao;
  TcpSocketClient? _client;
  String? _activeHost;
  int? _activePort;
  int _nextRequestId = 0;
  final Map<int, Completer<Message>> _pendingRequests = {};
  StreamSubscription<Message>? _messageSubscription;

  static const Duration _scheduleRequestTimeout = Duration(seconds: 15);
  static const Duration _fileTransferTimeout = Duration(minutes: 5);
  static const Duration _backupExecutionTimeout = Duration(minutes: 10);

  final Map<int, _FileTransferState> _activeTransfers = {};
  final Map<int, _BackupProgressState> _activeBackups = {};
  final FileChunker _chunker = FileChunker();

  TcpSocketClient? get activeClient => _client;
  String? get activeHost => _activeHost;
  int? get activePort => _activePort;
  bool get isConnected => _client?.isConnected ?? false;
  ConnectionStatus get status =>
      _client?.status ?? ConnectionStatus.disconnected;
  Stream<Message>? get messageStream => _client?.messageStream;
  Stream<ConnectionStatus>? get statusStream => _client?.statusStream;

  Future<void> connect({
    required String host,
    required int port,
    String? serverId,
    String? password,
    bool enableAutoReconnect = false,
  }) async {
    await disconnect();
    _client = TcpSocketClient();
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
  }

  void _onMessage(Message message) {
    final requestId = message.header.requestId;
    final transferState = _activeTransfers[requestId];
    if (transferState != null) {
      _handleFileTransferMessage(requestId, message, transferState);
      return;
    }
    final backupState = _activeBackups[requestId];
    if (backupState != null) {
      _handleBackupProgressMessage(message, backupState);
      return;
    }
    final completer = _pendingRequests.remove(requestId);
    completer?.complete(message);
  }

  void _handleFileTransferMessage(
    int requestId,
    Message message,
    _FileTransferState state,
  ) {
    if (isFileTransferStartMetadata(message)) {
      state.fileName = getFileNameFromMetadata(message);
      state.totalChunks = getTotalChunksFromMetadata(message);
      return;
    }
    if (isFileChunkMessage(message)) {
      state.chunks.add(getFileChunkFromPayload(message));
      return;
    }
    if (isFileTransferProgressMessage(message)) {
      state.onProgress?.call(
        getCurrentChunkFromProgress(message),
        getTotalChunksFromProgress(message),
      );
      return;
    }
    if (isFileTransferCompleteMessage(message)) {
      _activeTransfers.remove(requestId);
      _completeFileTransfer(state);
      return;
    }
    if (isFileTransferErrorMessage(message)) {
      _activeTransfers.remove(requestId);
      state.completer.complete(
        rd.Failure(Exception(getErrorFromFileTransferError(message))),
      );
    }
  }

  Future<void> _completeFileTransfer(_FileTransferState state) async {
    try {
      await _chunker.assembleChunks(state.chunks, state.outputPath);
      state.completer.complete(const rd.Success(rd.unit));
    } on Object catch (e) {
      state.completer.complete(
        rd.Failure(e is Exception ? e : Exception(e.toString())),
      );
    }
  }

  void _handleBackupProgressMessage(Message message, _BackupProgressState state) {
    if (isBackupProgressMessage(message)) {
      final step = getStepFromBackupProgress(message) ?? '';
      final progressMessage = getMessageFromBackupProgress(message) ?? '';
      final progress = getProgressFromBackupProgress(message) ?? 0.0;
      state.onProgress?.call(step, progressMessage, progress);
      return;
    }
    if (isBackupCompleteMessage(message)) {
      _activeBackups.remove(message.header.requestId);
      state.onProgress?.call('Concluído', 'Backup concluído com sucesso!', 1);
      state.completer.complete(const rd.Success(rd.unit));
      return;
    }
    if (isBackupFailedMessage(message)) {
      _activeBackups.remove(message.header.requestId);
      final error = getErrorFromBackupFailed(message) ?? 'Erro desconhecido';
      state.completer.complete(rd.Failure(Exception(error)));
      return;
    }
  }

  Future<void> disconnect() async {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    for (final state in _activeTransfers.values) {
      if (!state.completer.isCompleted) {
        state.completer.complete(
          rd.Failure(Exception('Disconnected during file transfer')),
        );
      }
    }
    _activeTransfers.clear();
    for (final state in _activeBackups.values) {
      if (!state.completer.isCompleted) {
        state.completer.complete(
          rd.Failure(Exception('Disconnected during backup')),
        );
      }
    }
    _activeBackups.clear();
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Disconnected'));
      }
    }
    _pendingRequests.clear();
    if (_client != null) {
      await _client!.disconnect();
      _client = null;
      _activeHost = null;
      _activePort = null;
    }
  }

  Future<rd.Result<List<Schedule>>> listSchedules() async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(createListSchedulesMessage(requestId: requestId));
      final message = await completer.future.timeout(_scheduleRequestTimeout);
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type != MessageType.scheduleList) {
        return rd.Failure(
          Exception('Resposta inesperada: ${message.header.type.name}'),
        );
      }
      return rd.Success(getSchedulesFromListPayload(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('listSchedules timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<rd.Result<Schedule>> updateSchedule(Schedule schedule) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(
        createUpdateScheduleMessage(requestId: requestId, schedule: schedule),
      );
      final message = await completer.future.timeout(_scheduleRequestTimeout);
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type != MessageType.scheduleUpdated) {
        return rd.Failure(
          Exception('Resposta inesperada: ${message.header.type.name}'),
        );
      }
      return rd.Success(getScheduleFromUpdatePayload(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('updateSchedule timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<rd.Result<List<RemoteFileEntry>>> listAvailableFiles() async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(createListFilesMessage(requestId: requestId));
      final message = await completer.future.timeout(_scheduleRequestTimeout);
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type != MessageType.fileList) {
        return rd.Failure(
          Exception('Resposta inesperada: ${message.header.type.name}'),
        );
      }
      return rd.Success(getFileListFromPayload(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('listAvailableFiles timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<rd.Result<void>> requestFile({
    required String filePath,
    required String outputPath,
    String? scheduleId,
    void Function(int currentChunk, int totalChunks)? onProgress,
  }) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<rd.Result<void>>();
    _activeTransfers[requestId] = _FileTransferState(
      completer: completer,
      outputPath: outputPath,
      chunks: [],
      onProgress: onProgress,
    );
    try {
      await send(
        createFileTransferStartRequestMessage(
          requestId: requestId,
          filePath: filePath,
          scheduleId: scheduleId,
        ),
      );
      return await completer.future.timeout(_fileTransferTimeout);
    } on TimeoutException {
      _activeTransfers.remove(requestId);
      return rd.Failure(TimeoutException('requestFile timeout'));
    } on Object catch (e) {
      _activeTransfers.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<rd.Result<void>> executeSchedule(
    String scheduleId, {
    BackupProgressCallback? onProgress,
  }) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<rd.Result<void>>();

    if (onProgress != null) {
      _activeBackups[requestId] = _BackupProgressState(
        completer: completer,
        onProgress: onProgress,
      );
    }

    try {
      await send(
        createExecuteScheduleMessage(
          requestId: requestId,
          scheduleId: scheduleId,
        ),
      );

      if (onProgress == null) {
        final message = await completer.future.timeout(_backupExecutionTimeout);
        _activeBackups.remove(requestId);
        if (message is rd.Result) {
          return message as rd.Result<void>;
        }
        return const rd.Success(rd.unit);
      }

      final result = await completer.future.timeout(_backupExecutionTimeout);
      _activeBackups.remove(requestId);
      return result;
    } on TimeoutException {
      _activeBackups.remove(requestId);
      return rd.Failure(
        TimeoutException(
          'Tempo esgotado ao aguardar conclusão do backup '
          '(limite: ${_backupExecutionTimeout.inMinutes} minutos)',
        ),
      );
    } on Object catch (e) {
      _activeBackups.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<rd.Result<Map<String, dynamic>>> getServerMetrics() async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(createMetricsRequestMessage(requestId: requestId));
      final message = await completer.future.timeout(_scheduleRequestTimeout);
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type != MessageType.metricsResponse) {
        return rd.Failure(
          Exception(
            'Resposta inesperada: ${message.header.type.name}',
          ),
        );
      }
      return rd.Success(getMetricsFromPayload(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('getServerMetrics timeout'));
    } on Object catch (e) {
      _pendingRequests.remove(requestId);
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<void> send(Message message) async {
    final client = _client;
    if (client == null || !client.isConnected) {
      throw StateError('ConnectionManager not connected');
    }
    await client.send(message);
  }

  Future<List<ServerConnectionsTableData>> getSavedConnections() async {
    if (_serverConnectionDao == null) {
      return <ServerConnectionsTableData>[];
    }
    return _serverConnectionDao.getAll();
  }

  Future<void> connectToSavedConnection(
    String connectionId, {
    bool enableAutoReconnect = false,
  }) async {
    final dao = _serverConnectionDao;
    if (dao == null) {
      throw StateError(
        'ConnectionManager has no ServerConnectionDao; cannot connect to saved connection',
      );
    }
    final connection = await dao.getById(connectionId);
    if (connection == null) {
      throw StateError('Saved connection not found: $connectionId');
    }
    await connect(
      host: connection.host,
      port: connection.port,
      serverId: connection.serverId,
      password: connection.password,
      enableAutoReconnect: enableAutoReconnect,
    );
  }
}

class _FileTransferState {
  _FileTransferState({
    required this.completer,
    required this.outputPath,
    required this.chunks,
    this.onProgress,
  });

  final Completer<rd.Result<void>> completer;
  final String outputPath;
  final List<FileChunk> chunks;
  final void Function(int currentChunk, int totalChunks)? onProgress;
  String fileName = '';
  int totalChunks = 0;
}

class _BackupProgressState {
  _BackupProgressState({
    required this.completer,
    this.onProgress,
  });

  final Completer<rd.Result<void>> completer;
  final BackupProgressCallback? onProgress;
}
