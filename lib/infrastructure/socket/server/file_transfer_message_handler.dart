import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/remote_file_entry.dart';
import 'package:backup_database/domain/services/i_file_transfer_lock_service.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/file_chunker.dart';
import 'package:backup_database/infrastructure/protocol/file_transfer_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/socket/server/remote_staging_artifact_ttl.dart';
import 'package:path/path.dart' as p;

typedef SendToClient = Future<void> Function(String clientId, Message message);

class FileTransferMessageHandler {
  FileTransferMessageHandler({
    required String allowedBasePath,
    required IFileTransferLockService lockService,
    FileChunker? chunker,
    RemoteStagingArtifactTtl? remoteStagingArtifactTtl,
  }) : _allowedBasePath = p.normalize(p.absolute(allowedBasePath)),
       _lockService = lockService,
       _chunker = chunker ?? FileChunker(),
       _remoteArtifactTtl = remoteStagingArtifactTtl ?? RemoteStagingArtifactTtl();

  final String _allowedBasePath;
  final IFileTransferLockService _lockService;
  final FileChunker _chunker;
  final RemoteStagingArtifactTtl _remoteArtifactTtl;

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    if (isListFilesRequest(message)) {
      await _handleListFiles(clientId, message, sendToClient);
      return;
    }
    if (!isFileTransferStartRequest(message)) return;

    final requestId = message.header.requestId;
    final filePath = getFilePathFromRequest(message);
    final startChunk = getStartChunkFromRequest(message);
    final runId = getRunIdFromFileTransferRequest(message);

    // Adquire lease (PR-4: owner = sessão, runId opcional p/ re-sync)
    final lockAcquired = await _lockService.tryAcquireLock(
      filePath,
      owner: clientId,
      runId: runId,
    );
    if (!lockAcquired) {
      await sendToClient(
        clientId,
        createFileTransferErrorMessage(
          requestId: requestId,
          errorMessage:
              'Arquivo está sendo baixado por outro cliente. Tente novamente em alguns minutos.',
          errorCode: ErrorCode.fileBusy,
        ),
      );
      LoggerService.info(
        'File transfer rejected: file locked for $filePath by client $clientId',
      );
      return;
    }

    try {
      final resolved = p.isAbsolute(filePath)
          ? p.normalize(p.absolute(filePath))
          : p.normalize(p.join(_allowedBasePath, filePath));
      if (!_isPathAllowed(resolved)) {
        await sendToClient(
          clientId,
          createFileTransferErrorMessage(
            requestId: requestId,
            errorMessage: 'Path not allowed',
            errorCode: ErrorCode.pathNotAllowed,
          ),
        );
        return;
      }

      final entityType = await FileSystemEntity.type(resolved);
      if (entityType == FileSystemEntityType.notFound) {
        await sendToClient(
          clientId,
          createFileTransferErrorMessage(
            requestId: requestId,
            errorMessage: 'File not found',
            errorCode: ErrorCode.fileNotFound,
          ),
        );
        return;
      }

      File? tempZipFile;
      late final String pathToChunk;
      late final String transferFileName;

      if (entityType == FileSystemEntityType.file) {
        if (isPathUnderRemoteStaging(_allowedBasePath, resolved) &&
            await _remoteArtifactTtl.isFileExpiredByRetention(File(resolved))) {
          await sendToClient(
            clientId,
            createFileTransferErrorMessage(
              requestId: requestId,
              errorMessage: ErrorCode.artifactExpired.defaultMessage,
              errorCode: ErrorCode.artifactExpired,
            ),
          );
          return;
        }
        pathToChunk = resolved;
        transferFileName = p.basename(resolved);
      } else if (entityType == FileSystemEntityType.directory) {
        if (isPathUnderRemoteStaging(_allowedBasePath, resolved) &&
            await _remoteArtifactTtl
                .isDirectoryExpiredByNewestFile(Directory(resolved))) {
          await sendToClient(
            clientId,
            createFileTransferErrorMessage(
              requestId: requestId,
              errorMessage: ErrorCode.artifactExpired.defaultMessage,
              errorCode: ErrorCode.artifactExpired,
            ),
          );
          return;
        }
        final zipPath = await _zipDirectoryForTransfer(Directory(resolved));
        if (zipPath == null) {
          await sendToClient(
            clientId,
            createFileTransferErrorMessage(
              requestId: requestId,
              errorMessage: 'Failed to prepare folder for transfer',
            ),
          );
          return;
        }
        tempZipFile = File(zipPath);
        pathToChunk = zipPath;
        transferFileName = '${p.basename(resolved)}.zip';
      } else {
        await sendToClient(
          clientId,
          createFileTransferErrorMessage(
            requestId: requestId,
            errorMessage: 'File not found',
            errorCode: ErrorCode.fileNotFound,
          ),
        );
        return;
      }

      final transferFile = File(pathToChunk);
      if (!await transferFile.exists()) {
        await sendToClient(
          clientId,
          createFileTransferErrorMessage(
            requestId: requestId,
            errorMessage: 'File not found',
            errorCode: ErrorCode.fileNotFound,
          ),
        );
        return;
      }

      try {
        final fileSize = await transferFile.length();
        LoggerService.info(
          '[FileTransferHandler] Iniciando transferência: '
          '$transferFileName ($fileSize bytes) para cliente $clientId',
        );
        LoggerService.info(
          '[FileTransferHandler] startChunk solicitado pelo cliente: '
          '$startChunk',
        );

        final normalizedStartChunk = startChunk < 0 ? 0 : startChunk;
        final totalChunks = fileSize == 0
            ? 1
            : (fileSize / _chunker.chunkSize).ceil();
        final effectiveStartChunk = normalizedStartChunk > totalChunks
            ? totalChunks
            : normalizedStartChunk;
        LoggerService.info(
          '[FileTransferHandler] Arquivo em $totalChunks chunks (streaming)',
        );
        if (effectiveStartChunk != startChunk) {
          LoggerService.warning(
            '[FileTransferHandler] startChunk ajustado de '
            '$startChunk para $effectiveStartChunk',
          );
        }

        await sendToClient(
          clientId,
          createFileTransferStartMetadataMessage(
            requestId: requestId,
            fileName: transferFileName,
            fileSize: fileSize,
            totalChunks: totalChunks,
            chunkSize: _chunker.chunkSize,
          ),
        );
        LoggerService.info(
          '[FileTransferHandler] Metadados enviados: '
          'fileName=$transferFileName, fileSize=$fileSize, '
          'totalChunks=$totalChunks',
        );

        // Antes existiam dois `Future.delayed(5ms)` por chunk como
        // backpressure manual. Para um arquivo de 50 GB com chunks de
        // 64 KB isso adicionava ~4000s só esperando. Agora confiamos em
        // `await sendToClient` (que respeita o `_sendQueue` do socket
        // e o `flush`), que naturalmente aplica back-pressure quando o
        // peer não consegue acompanhar.
        var sentIndex = effectiveStartChunk;
        // Throttle do log de progresso: emitir info por chunk produzia
        // centenas de milhares de linhas em transferências grandes.
        var lastProgressLog = DateTime.now();
        var lastLoggedPercent = -1;
        const progressLogInterval = Duration(seconds: 2);

        await _chunker.forEachChunk(
          pathToChunk,
          firstChunkIndex: effectiveStartChunk,
          emit: (chunk) async {
            LoggerService.debug(
              '[FileTransferHandler] Enviando chunk ${chunk.chunkIndex + 1}/'
              '${chunk.totalChunks}: ${chunk.data.length} bytes',
            );
            await sendToClient(
              clientId,
              createFileChunkMessage(requestId: requestId, chunk: chunk),
            );

            sentIndex = chunk.chunkIndex + 1;
            await sendToClient(
              clientId,
              createFileTransferProgressMessage(
                requestId: requestId,
                currentChunk: sentIndex,
                totalChunks: chunk.totalChunks,
              ),
            );

            // Log de progresso em info a cada 2s OU a cada milestone de 10%
            // (10, 20, 30...). Antes era `percent % 10 == 0`, que para
            // arquivos grandes (50 GB ÷ 64 KB chunks ≈ 780k chunks) fazia
            // 7.8k linhas consecutivas em cada milestone — em vez de 1.
            // Agora rastreamos `lastLoggedPercent` para garantir que cada
            // milestone seja logado uma única vez.
            final now = DateTime.now();
            final percent = (sentIndex / chunk.totalChunks * 100).floor();
            final isNewMilestone = percent >= lastLoggedPercent + 10;
            final isTimeBased =
                now.difference(lastProgressLog) >= progressLogInterval;
            if (isNewMilestone || isTimeBased) {
              LoggerService.info(
                '[FileTransferHandler] $sentIndex/${chunk.totalChunks} '
                'chunks ($percent%)',
              );
              lastProgressLog = now;
              if (isNewMilestone) lastLoggedPercent = percent;
            }
          },
        );

        await sendToClient(
          clientId,
          createFileTransferCompleteMessage(requestId: requestId),
        );
        LoggerService.info(
          '[FileTransferHandler] ✓ Transferência concluída: '
          '$transferFileName ($totalChunks chunks) para cliente $clientId',
        );
      } finally {
        if (tempZipFile != null) {
          try {
            if (await tempZipFile.exists()) {
              await tempZipFile.delete();
            }
          } on Object catch (e, st) {
            LoggerService.debug(
              '[FileTransferHandler] temp zip delete: $e',
              e,
              st,
            );
          }
        }
      }
    } on Object catch (e, st) {
      LoggerService.warning(
        'FileTransferMessageHandler error for client $clientId',
        e,
        st,
      );
      await sendToClient(
        clientId,
        createFileTransferErrorMessage(
          requestId: requestId,
          errorMessage: e.toString(),
        ),
      );
    } finally {
      // Sempre libera o lock, mesmo em caso de erro
      await _lockService.releaseLock(filePath);
    }
  }

  bool _isPathAllowed(String resolvedPath) {
    final normalized = p.normalize(p.absolute(resolvedPath));
    return normalized == _allowedBasePath ||
        p.isWithin(_allowedBasePath, normalized);
  }

  Future<String?> _zipDirectoryForTransfer(Directory source) async {
    final base = p.basename(source.path);
    final safe = base
        .replaceAll(RegExp(r'[^\w\-.]+'), '_')
        .replaceAll(RegExp('_+'), '_');
    final zipPath = p.join(
      Directory.systemTemp.path,
      'bd_transfer_${DateTime.now().microsecondsSinceEpoch}_$safe.zip',
    );
    final encoder = ZipFileEncoder();
    final normalizedDir = p.normalize(source.path);
    try {
      encoder.create(zipPath);
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          final relativePath = p.relative(
            entity.path,
            from: normalizedDir,
          );
          encoder.addFile(entity, relativePath);
        }
      }
      encoder.close();
      return zipPath;
    } on Object catch (e, st) {
      LoggerService.warning(
        'FileTransferMessageHandler: zip directory failed',
        e,
        st,
      );
      try {
        encoder.close();
      } on Object catch (e, st) {
        LoggerService.debug(
          'FileTransferMessageHandler: zip encoder close: $e',
          e,
          st,
        );
      }
      try {
        final zf = File(zipPath);
        if (await zf.exists()) {
          await zf.delete();
        }
      } on Object catch (e, st) {
        LoggerService.debug(
          'FileTransferMessageHandler: zip partial delete: $e',
          e,
          st,
        );
      }
      return null;
    }
  }

  Future<void> _handleListFiles(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final requestId = message.header.requestId;
    try {
      final dir = Directory(_allowedBasePath);
      if (!await dir.exists()) {
        await sendToClient(
          clientId,
          createFileListMessage(
            requestId: requestId,
            files: [],
            error: 'Directory not found',
            errorCode: ErrorCode.directoryNotFound,
          ),
        );
        return;
      }
      final files = await _listFilesRecursive(dir, _allowedBasePath);
      await sendToClient(
        clientId,
        createFileListMessage(requestId: requestId, files: files),
      );
    } on FileSystemException catch (e, st) {
      LoggerService.warning(
        'FileTransferMessageHandler listFiles error for client $clientId',
        e,
        st,
      );
      await sendToClient(
        clientId,
        createFileListMessage(
          requestId: requestId,
          files: [],
          error: 'Failed to list files: ${e.message}',
          errorCode: ErrorCode.ioError,
        ),
      );
    } on Object catch (e, st) {
      LoggerService.warning(
        'FileTransferMessageHandler listFiles error for client $clientId',
        e,
        st,
      );
      await sendToClient(
        clientId,
        createFileListMessage(
          requestId: requestId,
          files: [],
          error: 'Failed to list files: $e',
          errorCode: ErrorCode.unknown,
        ),
      );
    }
  }

  Future<List<RemoteFileEntry>> _listFilesRecursive(
    Directory dir,
    String basePath,
  ) async {
    final result = <RemoteFileEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        final stat = await entity.stat();
        final fullPath = p.normalize(entity.path);
        final relativePath = p.relative(fullPath, from: basePath);
        result.add(
          RemoteFileEntry(
            path: relativePath,
            size: stat.size,
            lastModified: stat.modified,
          ),
        );
      } else if (entity is Directory) {
        result.addAll(
          await _listFilesRecursive(entity, basePath),
        );
      }
    }
    return result;
  }
}
