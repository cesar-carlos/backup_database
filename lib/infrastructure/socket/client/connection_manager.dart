import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/logging.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/remote_file_entry.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/datasources/daos/server_connection_dao.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/protocol/file_transfer_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/metrics_messages.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/client/socket_client_service.dart';
import 'package:backup_database/infrastructure/socket/client/tcp_socket_client.dart';
import 'package:crypto/crypto.dart';
import 'package:result_dart/result_dart.dart' as rd;

typedef BackupProgressCallback =
    void Function(
      String step,
      String message,
      double progress,
    );

class ConnectionManager {
  ConnectionManager({ServerConnectionDao? serverConnectionDao})
    : _serverConnectionDao = serverConnectionDao,
      _socketLogger = di.getIt<SocketLoggerService>();

  final ServerConnectionDao? _serverConnectionDao;
  final SocketLoggerService _socketLogger;
  TcpSocketClient? _client;
  String? _activeHost;
  int? _activePort;
  int _nextRequestId = 0;
  final Map<int, Completer<Message>> _pendingRequests = {};
  StreamSubscription<Message>? _messageSubscription;

  final Map<int, _FileTransferState> _activeTransfers = {};
  final Map<int, _BackupProgressState> _activeBackups = {};

  // Getter para verificar se há transferências ativas (usado pelo heartbeat)
  bool get hasActiveTransfers => _activeTransfers.isNotEmpty;

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
      state.isCompressed = getIsCompressedFromMetadata(message);

      // Validar SHA-256 (Fase 2)
      if (message.payload.containsKey('hash')) {
        state.expectedHash = message.payload['hash'] as String?;
      }

      LoggerService.info(
        '[ConnectionManager] Metadata recebida: ${state.fileName}, chunks: ${state.totalChunks}, compressed: ${state.isCompressed}',
      );
      return;
    }
    if (isFileChunkMessage(message)) {
      final chunk = getFileChunkFromPayload(message);
      var dataToWrite = chunk.data;

      // Decompressão (Fase 3)
      if (state.isCompressed) {
        try {
          dataToWrite = Uint8List.fromList(gzip.decode(chunk.data));
          LoggerService.debug(
            '[ConnectionManager] Chunk descomprimido: ${chunk.data.length} -> ${dataToWrite.length} bytes',
          );
        } on Object catch (e) {
          LoggerService.error(
            '[ConnectionManager] Falha ao descomprimir chunk ${chunk.chunkIndex}: $e',
          );
          _cleanupTransfer(requestId);
          state.completer.complete(
            rd.Failure(Exception('Falha na descompressão GZIP: $e')),
          );
          return;
        }
      }

      // Streaming: Escrever diretamente no sink
      state.fileSink.add(dataToWrite);
      if (chunk.chunkIndex % 10 == 0) {
        // Flush periódico opcional
      }

      LoggerService.debug(
        '[ConnectionManager] Chunk ${chunk.chunkIndex}/${chunk.totalChunks} recebido e escrito: ${chunk.data.length} bytes',
      );
      return;
    }
    if (isFileTransferProgressMessage(message)) {
      final current = getCurrentChunkFromProgress(message);
      final total = getTotalChunksFromProgress(message);
      state.onProgress?.call(current, total);
      LoggerService.debug('[ConnectionManager] Progresso: $current/$total');
      return;
    }
    if (isFileTransferCompleteMessage(message)) {
      LoggerService.info(
        '[ConnectionManager] Transferência completa recebida, finalizando arquivo...',
      );
      _activeTransfers.remove(requestId);
      _completeFileTransfer(state);
      return;
    }
    if (isFileTransferErrorMessage(message)) {
      final error = getErrorFromFileTransferError(message);
      LoggerService.error(
        '[ConnectionManager] Erro de transferência recebido: $error',
      );
      _cleanupTransfer(requestId);
      state.completer.complete(
        rd.Failure(Exception(error)),
      );
    }
  }

  Future<void> _completeFileTransfer(_FileTransferState state) async {
    LoggerService.info('[ConnectionManager] _completeFileTransfer iniciado');
    LoggerService.info('[ConnectionManager] OutputPath: ${state.outputPath}');

    try {
      // Finalizar escrita no .part
      await state.fileSink.flush();
      await state.fileSink.close();

      final partFile = File(state.partFilePath);
      final finalFile = File(state.outputPath);

      // Verificar tamanho do arquivo baixado
      final partSize = await partFile.length();
      LoggerService.info(
        '[ConnectionManager] Tamanho do arquivo parcial: $partSize bytes',
      );

      // Validar SHA-256 (Fase 2)
      if (state.expectedHash != null && state.expectedHash!.isNotEmpty) {
        LoggerService.info(
          '[ConnectionManager] Calculando SHA-256 para validação...',
        );
        final digest = await sha256.bind(partFile.openRead()).first;
        final actualHash = digest.toString();

        if (actualHash != state.expectedHash) {
          LoggerService.error(
            '[ConnectionManager] SHA-256 Checksum FALHOU! Esperado: ${state.expectedHash}, Calculado: $actualHash',
          );
          await partFile.delete(); // Deletar arquivo corrompido
          throw FileSystemException(
            'Falha de integridade: SHA-256 inválido.',
            state.outputPath,
          );
        }
        LoggerService.info(
          '[ConnectionManager] SHA-256 Verificado com sucesso.',
        );
      } else {
        LoggerService.warning(
          '[ConnectionManager] SHA-256 não disponível no metadata. Integridade não verificada.',
        );
      }

      // Rename Atômico: .part -> Final
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(state.outputPath);
      LoggerService.info(
        '[ConnectionManager] ✓ Arquivo renomeado e salvo com sucesso!',
      );

      state.completer.complete(const rd.Success(rd.unit));
    } on Object catch (e) {
      LoggerService.error('[ConnectionManager] ✗ Erro ao salvar arquivo: $e');
      state.completer.complete(
        rd.Failure(e is Exception ? e : Exception(e.toString())),
      );
    }
  }

  void _handleBackupProgressMessage(
    Message message,
    _BackupProgressState state,
  ) {
    // Log para rastrear tipo de mensagem recebida
    LoggerService.info(
      '[ConnectionManager._handleBackupProgressMessage] Tipo: ${message.header.type.name}, RequestID: ${message.header.requestId}',
    );
    LoggerService.info(
      '[ConnectionManager._handleBackupProgressMessage] Payload: ${message.payload}',
    );

    if (isBackupProgressMessage(message)) {
      final step = getStepFromBackupProgress(message) ?? '';
      final progressMessage = getMessageFromBackupProgress(message) ?? '';
      final progress = getProgressFromBackupProgress(message) ?? 0.0;
      state.onProgress?.call(step, progressMessage, progress);
      return;
    }
    if (isBackupCompleteMessage(message)) {
      LoggerService.info(
        '[ConnectionManager] ✓ Mensagem backupComplete recebida!',
      );
      final path = getBackupPathFromBackupComplete(message);
      LoggerService.info('[ConnectionManager] backupPath extraído: "$path"');
      _activeBackups.remove(message.header.requestId);
      state.onProgress?.call('Concluído', 'Backup concluído com sucesso!', 1);
      if (!state.completer.isCompleted) {
        state.completer.complete(rd.Success(path ?? ''));
      }
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
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
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
    } on Object catch (e, stackTrace) {
      _pendingRequests.remove(requestId);
      LoggerService.warning(
        '[ConnectionManager] listSchedules falhou',
        e,
        stackTrace,
      );
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
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
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
    } on Object catch (e, stackTrace) {
      _pendingRequests.remove(requestId);
      LoggerService.warning(
        '[ConnectionManager] updateSchedule falhou',
        e,
        stackTrace,
      );
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
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
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
    } on Object catch (e, stackTrace) {
      _pendingRequests.remove(requestId);
      LoggerService.warning(
        '[ConnectionManager] listAvailableFiles falhou',
        e,
        stackTrace,
      );
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<rd.Result<void>> requestFile({
    required String filePath,
    required String outputPath,
    String? scheduleId,
    void Function(int currentChunk, int totalChunks)? onProgress,
  }) async {
    LoggerService.info('[ConnectionManager] requestFile chamado');
    LoggerService.info('[ConnectionManager] filePath: $filePath');
    LoggerService.info('[ConnectionManager] outputPath: $outputPath');
    LoggerService.info('[ConnectionManager] scheduleId: $scheduleId');

    if (!isConnected) {
      LoggerService.error('[ConnectionManager] Não conectado!');
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    LoggerService.info('[ConnectionManager] Conectado ✓');

    final requestId = _nextRequestId++;
    LoggerService.info('[ConnectionManager] RequestID: $requestId');

    final completer = Completer<rd.Result<void>>();

    // Resume Logic: Check for .part file
    final partFilePath = '$outputPath.part';
    final partFile = File(partFilePath);
    var startChunk = 0;
    IOSink? fileSink;

    try {
      if (await partFile.exists()) {
        final partSize = await partFile.length();
        if (partSize > 0) {
          // Assume o chunk size padrão.
          // TODO(dev): Armazenar metadados do download anterior para garantir mesmo chunk size.
          // Por enquanto assumimos que o config não muda.
          startChunk = (partSize / SocketConfig.chunkSize).floor();
          final validSize = startChunk * SocketConfig.chunkSize;

          LoggerService.info(
            '[ConnectionManager] Arquivo parcial encontrado. Resume do chunk $startChunk ($validSize bytes)',
          );

          // Truncar para o último limite de chunk válido para evitar corrupção
          fileSink = partFile.openWrite(mode: FileMode.append);
          // Nota: O ideal seria truncar, mas append funciona se o server mandar a partir do offset correto.
          // Se o server mandar startChunk, ele manda o chunk *inteiro*.
          // Se o arquivo local tiver bytes extras (chunk incompleto), precisamos aparar.
          // Vamos fazer um truncate manual antes de abrir o sink.
          if (partSize != validSize) {
            LoggerService.info(
              '[ConnectionManager] Truncando arquivo parcial de $partSize para $validSize bytes',
            );
            final raf = await partFile.open(
              mode: FileMode.write,
            ); // write mode aqui pode limpar. Cuidado.
            await raf.setPosition(validSize);
            await raf.truncate(validSize);
            await raf.close();
          }
        }
      }

      fileSink ??= partFile.openWrite(mode: FileMode.append);

      _activeTransfers[requestId] = _FileTransferState(
        completer: completer,
        outputPath: outputPath,
        partFilePath: partFilePath,
        fileSink: fileSink,
        onProgress: onProgress,
      );

      LoggerService.info(
        '[ConnectionManager] Enviando requisição de transferência (startChunk: $startChunk)...',
      );
      await send(
        createFileTransferStartRequestMessage(
          requestId: requestId,
          filePath: filePath,
          scheduleId: scheduleId,
          startChunk: startChunk,
        ),
      );
      LoggerService.info(
        '[ConnectionManager] Requisição enviada, aguardando resposta...',
      );

      final result = await completer.future.timeout(
        SocketConfig.fileTransferTimeout,
      );
      LoggerService.info('[ConnectionManager] Transferência completada!');
      return result;
    } on TimeoutException {
      _cleanupTransfer(requestId);
      LoggerService.error('[ConnectionManager] Timeout na transferência!');
      return rd.Failure(TimeoutException('requestFile timeout'));
    } on Object catch (e) {
      _cleanupTransfer(requestId);
      LoggerService.error('[ConnectionManager] Erro na transferência: $e');
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  void _cleanupTransfer(int requestId) {
    final state = _activeTransfers.remove(requestId);
    if (state != null) {
      state.fileSink.close(); // Fecha o arquivo para liberar lock
    }
  }

  Future<rd.Result<String>> executeSchedule(
    String scheduleId, {
    BackupProgressCallback? onProgress,
  }) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<rd.Result<String>>();

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
        final result = await completer.future.timeout(
          SocketConfig.backupExecutionTimeout,
        );
        _activeBackups.remove(requestId);
        return result;
      }

      final result = await completer.future.timeout(
        SocketConfig.backupExecutionTimeout,
      );
      _activeBackups.remove(requestId);
      return result;
    } on TimeoutException {
      _activeBackups.remove(requestId);
      return rd.Failure(
        TimeoutException(
          'Tempo esgotado ao aguardar conclusão do backup '
          '(limite: ${SocketConfig.backupExecutionTimeout.inMinutes} minutos)',
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
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
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

  Future<rd.Result<void>> cancelSchedule(String scheduleId) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    try {
      await send(
        createCancelScheduleMessage(
          requestId: requestId,
          scheduleId: scheduleId,
        ),
      );
      final message = await completer.future.timeout(
        SocketConfig.scheduleRequestTimeout,
      );
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (message.header.type != MessageType.scheduleCancelled) {
        return rd.Failure(
          Exception(
            'Resposta inesperada: ${message.header.type.name}',
          ),
        );
      }
      return const rd.Success(rd.unit);
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('cancelSchedule timeout'));
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
    required this.partFilePath,
    required this.fileSink,
    this.onProgress,
  });

  final Completer<rd.Result<void>> completer;
  final String outputPath;
  final String partFilePath;
  final IOSink fileSink;
  final void Function(int currentChunk, int totalChunks)? onProgress;
  String fileName = '';
  int totalChunks = 0;
  String? expectedHash;
  bool isCompressed = false;
}

class _BackupProgressState {
  _BackupProgressState({
    required this.completer,
    this.onProgress,
  });

  final Completer<rd.Result<String>> completer;
  final BackupProgressCallback? onProgress;
}
