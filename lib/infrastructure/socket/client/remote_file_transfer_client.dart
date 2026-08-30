import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/remote_file_entry.dart';
import 'package:backup_database/infrastructure/protocol/file_transfer_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/client/client_rpc_transport.dart';
import 'package:backup_database/infrastructure/socket/client/file_transfer_resume_metadata_store.dart';
import 'package:crypto/crypto.dart';
import 'package:result_dart/result_dart.dart' as rd;

class FileTransferState {
  FileTransferState({
    required this.completer,
    required this.outputPath,
    required this.partFilePath,
    required this.sourceFilePath,
    required this.scheduleId,
    required this.transferChunkSize,
    required this.fileSink,
    this.onProgress,
    this.runId,
  });

  final Completer<rd.Result<void>> completer;
  final String outputPath;
  final String partFilePath;
  final String sourceFilePath;
  final String? scheduleId;
  final String? runId;
  final IOSink fileSink;
  final void Function(int currentChunk, int totalChunks)? onProgress;
  String fileName = '';
  int totalChunks = 0;
  int expectedSize = 0;
  String? expectedHash;
  bool isCompressed = false;
  int transferChunkSize;
  int lastLoggedTransferPercent = -1;
  int lastLoggedProgressPercent = -1;
  Timer? _idleWatchdog;

  void resetIdleWatchdog(Duration timeout, void Function() onTimeout) {
    _idleWatchdog?.cancel();
    _idleWatchdog = Timer(timeout, onTimeout);
  }

  void cancelIdleWatchdog() {
    _idleWatchdog?.cancel();
    _idleWatchdog = null;
  }
}

class RemoteFileTransferClient {
  RemoteFileTransferClient({
    required this._rpc,
    required this._isConnected,
    required this._send,
    required this._isResumeSupported,
    required this._resumeMetadataStore,
    required this._idleTimeout,
  });

  final ClientRpcTransport _rpc;
  final bool Function() _isConnected;
  final Future<void> Function(Message message) _send;
  final bool Function() _isResumeSupported;
  final FileTransferResumeMetadataStore _resumeMetadataStore;
  final Duration _idleTimeout;
  final Map<int, FileTransferState> _activeTransfers = {};

  bool get hasActiveTransfers => _activeTransfers.isNotEmpty;
  int get activeCount => _activeTransfers.length;

  FileTransferState? transferFor(int requestId) => _activeTransfers[requestId];

  Future<rd.Result<List<RemoteFileEntry>>> listAvailableFiles() {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createListFilesMessage(requestId: requestId),
      isExpected: (message) => message.header.type == MessageType.fileList,
      parse: getFileListFromPayload,
      operationName: 'listAvailableFiles',
      logFailures: true,
    );
  }

  Future<void> abortAll(Object failure, {required bool closeSinks}) async {
    final transfers = Map<int, FileTransferState>.from(_activeTransfers);
    _activeTransfers.clear();
    for (final state in transfers.values) {
      if (!state.completer.isCompleted) {
        state.completer.complete(
          rd.Failure(failure is Exception ? failure : Exception('$failure')),
        );
      }
      state.cancelIdleWatchdog();
      if (closeSinks) {
        try {
          await state.fileSink.close();
        } on Object catch (e) {
          LoggerService.warning(
            '[ConnectionManager] Erro ao fechar fileSink durante disconnect: $e',
          );
        }
      }
    }
  }

  Future<rd.Result<void>> requestFile({
    required String filePath,
    required String outputPath,
    String? scheduleId,
    String? runId,
    void Function(int currentChunk, int totalChunks)? onProgress,
  }) async {
    LoggerService.info('[ConnectionManager] requestFile chamado');
    LoggerService.info('[ConnectionManager] filePath: $filePath');
    LoggerService.info('[ConnectionManager] outputPath: $outputPath');
    LoggerService.info('[ConnectionManager] scheduleId: $scheduleId');
    LoggerService.info('[ConnectionManager] runId: $runId');

    if (!_isConnected()) {
      LoggerService.error('[ConnectionManager] Não conectado!');
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    LoggerService.info('[ConnectionManager] Conectado ✓');

    final requestId = _rpc.allocateRequestId();
    LoggerService.info('[ConnectionManager] RequestID: $requestId');

    final completer = Completer<rd.Result<void>>();
    final partFilePath = '$outputPath.part';
    final partFile = File(partFilePath);
    var startChunk = 0;
    var transferChunkSize = SocketConfig.chunkSize;
    IOSink? fileSink;

    try {
      final partExists = await partFile.exists();
      final resumeMetadata = await _resumeMetadataStore.read(outputPath);

      if (partExists && !_isResumeSupported()) {
        LoggerService.info(
          '[ConnectionManager] Servidor sem suporte a resume; '
          'reiniciando download do zero.',
        );
        await partFile.delete();
        await _resumeMetadataStore.delete(outputPath);
      } else if (partExists) {
        if (resumeMetadata == null) {
          LoggerService.warning(
            '[ConnectionManager] Arquivo parcial descartado: '
            'metadata de resume ausente.',
          );
          await partFile.delete();
          await _resumeMetadataStore.delete(outputPath);
        } else if (!_canResumeWithMetadata(
          metadata: resumeMetadata,
          filePath: filePath,
          scheduleId: scheduleId,
          runId: runId,
        )) {
          LoggerService.warning(
            '[ConnectionManager] Arquivo parcial descartado: '
            'metadata de resume incompatível.',
          );
          await partFile.delete();
          await _resumeMetadataStore.delete(outputPath);
        } else if (resumeMetadata.chunkSize <= 0) {
          LoggerService.warning(
            '[ConnectionManager] Arquivo parcial descartado: '
            'chunkSize inválido no metadata de resume.',
          );
          await partFile.delete();
          await _resumeMetadataStore.delete(outputPath);
        } else {
          transferChunkSize = resumeMetadata.chunkSize;
          final partSize = await partFile.length();
          if (partSize > 0) {
            startChunk = (partSize / transferChunkSize).floor();
            final validSize = startChunk * transferChunkSize;
            LoggerService.info(
              '[ConnectionManager] Arquivo parcial encontrado. '
              'Resume do chunk $startChunk '
              '($validSize bytes, chunkSize=$transferChunkSize)',
            );
            if (partSize != validSize) {
              LoggerService.info(
                '[ConnectionManager] Truncando arquivo parcial '
                'de $partSize para $validSize bytes',
              );
              final raf = await partFile.open(mode: FileMode.append);
              await raf.truncate(validSize);
              await raf.close();
            }
          }
        }
      } else {
        await _resumeMetadataStore.delete(outputPath);
      }

      fileSink ??= partFile.openWrite(mode: FileMode.append);
      final state = FileTransferState(
        completer: completer,
        outputPath: outputPath,
        partFilePath: partFilePath,
        sourceFilePath: filePath,
        scheduleId: scheduleId,
        runId: runId,
        transferChunkSize: transferChunkSize,
        fileSink: fileSink,
        onProgress: onProgress,
      );
      _activeTransfers[requestId] = state;
      state.resetIdleWatchdog(
        _idleTimeout,
        () => _onTransferIdleTimeout(requestId, state),
      );

      LoggerService.info(
        '[ConnectionManager] Enviando requisição de transferência '
        '(startChunk: $startChunk, idleTimeout: '
        '${_idleTimeout.inSeconds}s, '
        'hardCeiling: ${SocketConfig.fileTransferHardTimeout.inMinutes}min)...',
      );
      await _send(
        createFileTransferStartRequestMessage(
          requestId: requestId,
          filePath: filePath,
          scheduleId: scheduleId,
          startChunk: startChunk,
          runId: runId,
        ),
      );
      LoggerService.info(
        '[ConnectionManager] Requisição enviada, aguardando resposta...',
      );

      final result = await completer.future.timeout(
        SocketConfig.fileTransferHardTimeout,
      );
      LoggerService.info('[ConnectionManager] Transferência completada!');
      return result;
    } on TimeoutException {
      await _cleanupTransfer(requestId);
      LoggerService.error(
        '[ConnectionManager] Hard ceiling de transferência atingido '
        '(${SocketConfig.fileTransferHardTimeout.inMinutes}min).',
      );
      return rd.Failure(
        TimeoutException('requestFile hard ceiling timeout'),
      );
    } on Object catch (e) {
      await _cleanupTransfer(requestId);
      LoggerService.error('[ConnectionManager] Erro na transferência: $e');
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }

  Future<void> handleMessage(
    int requestId,
    Message message,
    FileTransferState state,
  ) async {
    state.resetIdleWatchdog(
      _idleTimeout,
      () => _onTransferIdleTimeout(requestId, state),
    );

    if (isFileTransferStartMetadata(message)) {
      state.fileName = getFileNameFromMetadata(message);
      state.totalChunks = getTotalChunksFromMetadata(message);
      state.isCompressed = getIsCompressedFromMetadata(message);
      state.expectedSize = getFileSizeFromMetadata(message);
      state.transferChunkSize =
          getChunkSizeFromMetadata(message) ?? SocketConfig.chunkSize;
      if (state.transferChunkSize <= 0) {
        state.transferChunkSize = SocketConfig.chunkSize;
      }
      if (message.payload.containsKey('hash')) {
        state.expectedHash = getHashFromMetadata(message);
      }
      LoggerService.info(
        '[ConnectionManager] Metadata recebida: ${state.fileName}, '
        'chunks: ${state.totalChunks}, compressed: ${state.isCompressed}, '
        'expectedSize: ${state.expectedSize}, '
        'chunkSize: ${state.transferChunkSize}',
      );
      try {
        await _resumeMetadataStore.write(
          state.outputPath,
          FileTransferResumeMetadata(
            filePath: state.sourceFilePath,
            partFilePath: state.partFilePath,
            chunkSize: state.transferChunkSize,
            expectedSize: state.expectedSize > 0 ? state.expectedSize : null,
            expectedHash: state.expectedHash,
            isCompressed: state.isCompressed,
            scheduleId: state.scheduleId,
            runId: state.runId,
            updatedAt: DateTime.now(),
          ),
        );
      } on Object catch (e) {
        LoggerService.warning(
          '[ConnectionManager] Falha ao persistir metadata de resume: $e',
        );
      }
      return;
    }
    if (isFileChunkMessage(message)) {
      final chunk = getFileChunkFromPayload(message);
      var dataToWrite = chunk.data;
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
          await _cleanupTransfer(requestId);
          state.completer.complete(
            rd.Failure(Exception('Falha na descompressão GZIP: $e')),
          );
          return;
        }
      }
      state.fileSink.add(dataToWrite);
      final percent = (chunk.chunkIndex / chunk.totalChunks * 100).floor();
      final isNewMilestone = percent >= state.lastLoggedTransferPercent + 10;
      if (isNewMilestone) {
        LoggerService.debug(
          '[ConnectionManager] Transfer ${state.fileName} progresso: '
          '$percent% (${chunk.chunkIndex}/${chunk.totalChunks})',
        );
        state.lastLoggedTransferPercent = percent;
      }
      return;
    }
    if (isFileTransferProgressMessage(message)) {
      final current = getCurrentChunkFromProgress(message);
      final total = getTotalChunksFromProgress(message);
      state.onProgress?.call(current, total);
      final percent = total > 0 ? (current / total * 100).floor() : 0;
      final isNewMilestone = percent >= state.lastLoggedProgressPercent + 10;
      if (isNewMilestone) {
        LoggerService.debug(
          '[ConnectionManager] Progresso: $current/$total ($percent%)',
        );
        state.lastLoggedProgressPercent = percent;
      }
      return;
    }
    if (isFileTransferCompleteMessage(message)) {
      LoggerService.info(
        '[ConnectionManager] Transferência completa recebida, finalizando arquivo...',
      );
      _activeTransfers.remove(requestId);
      unawaited(_completeFileTransfer(state));
      return;
    }
    if (isFileTransferErrorMessage(message)) {
      final error = getErrorFromFileTransferError(message);
      LoggerService.error(
        '[ConnectionManager] Erro de transferência recebido: $error',
      );
      await _cleanupTransfer(requestId);
      state.completer.complete(rd.Failure(Exception(error)));
    }
  }

  bool _canResumeWithMetadata({
    required FileTransferResumeMetadata? metadata,
    required String filePath,
    required String? scheduleId,
    required String? runId,
  }) {
    if (metadata == null) {
      return true;
    }
    final sameFile = metadata.filePath == filePath;
    final sameSchedule = metadata.scheduleId == scheduleId;
    final sameRun = metadata.matchesRunId(runId);
    return sameFile && sameSchedule && sameRun;
  }

  void _onTransferIdleTimeout(int requestId, FileTransferState state) {
    if (!_activeTransfers.containsKey(requestId)) return;
    LoggerService.error(
      '[ConnectionManager] Transferência ociosa por mais que '
      '${_idleTimeout.inSeconds}s; abortando '
      '(runId=${state.runId ?? "—"}, fileName=${state.fileName}).',
    );
    if (!state.completer.isCompleted) {
      state.completer.complete(
        rd.Failure(
          TimeoutException(
            'Transferência sem progresso por '
            '${_idleTimeout.inSeconds}s',
          ),
        ),
      );
    }
    state.cancelIdleWatchdog();
  }

  Future<void> _cleanupTransfer(int requestId) async {
    final state = _activeTransfers.remove(requestId);
    if (state != null) {
      state.cancelIdleWatchdog();
      try {
        await state.fileSink.close();
      } on Object catch (e) {
        LoggerService.warning(
          '[ConnectionManager] Erro ao fechar fileSink durante cleanup: $e',
        );
      }
      try {
        final partExists = await File(state.partFilePath).exists();
        if (!partExists) {
          await _resumeMetadataStore.delete(state.outputPath);
        }
      } on Object catch (e) {
        LoggerService.warning(
          '[ConnectionManager] Erro ao limpar metadata de resume: $e',
        );
      }
    }
  }

  Future<void> _completeFileTransfer(FileTransferState state) async {
    LoggerService.info('[ConnectionManager] _completeFileTransfer iniciado');
    LoggerService.info('[ConnectionManager] OutputPath: ${state.outputPath}');
    state.cancelIdleWatchdog();
    try {
      await state.fileSink.flush();
      await state.fileSink.close();
      await _waitForFileRelease(state.partFilePath);
      final partFile = File(state.partFilePath);
      final finalFile = File(state.outputPath);
      final partSize = await partFile.length();
      LoggerService.info(
        '[ConnectionManager] Tamanho do arquivo parcial: $partSize bytes',
      );
      if (state.expectedSize > 0) {
        LoggerService.info(
          '[ConnectionManager] Validando tamanho: esperado=${state.expectedSize}, baixado=$partSize',
        );
        if (partSize != state.expectedSize) {
          LoggerService.error(
            '[ConnectionManager] Tamanho incorreto! Esperado: ${state.expectedSize}, Recebido: $partSize',
          );
          await partFile.delete();
          throw FileSystemException(
            'Tamanho do arquivo incorreto. Esperado: ${state.expectedSize}, Recebido: $partSize',
            state.outputPath,
          );
        }
        LoggerService.info(
          '[ConnectionManager] ✓ Tamanho validado com sucesso!',
        );
      } else {
        LoggerService.warning(
          '[ConnectionManager] Tamanho esperado não disponível no metadata. Pulando validação de tamanho.',
        );
      }
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
          await partFile.delete();
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
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(state.outputPath);
      LoggerService.info(
        '[ConnectionManager] ✓ Arquivo renomeado e salvo com sucesso!',
      );
      await _resumeMetadataStore.delete(state.outputPath);
      state.completer.complete(const rd.Success(rd.unit));
    } on Object catch (e) {
      LoggerService.error('[ConnectionManager] ✗ Erro ao salvar arquivo: $e');
      state.completer.complete(
        rd.Failure(e is Exception ? e : Exception(e.toString())),
      );
    }
  }

  Future<void> _waitForFileRelease(String filePath) async {
    const maxAttempts = 10;
    const delayMs = 100;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final file = File(filePath);
        final handle = await file.open();
        await handle.close();
        LoggerService.info(
          '[ConnectionManager] Arquivo liberado na tentativa ${attempt + 1}',
        );
        return;
      } on Object catch (e) {
        LoggerService.debug(
          '[ConnectionManager] Arquivo ainda travado (tentativa ${attempt + 1}): $e',
        );
        if (attempt < maxAttempts - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: delayMs * (attempt + 1)),
          );
        } else {
          LoggerService.warning(
            '[ConnectionManager] Arquivo ainda travado após $maxAttempts tentativas. Continuando...',
          );
        }
      }
    }
  }
}
