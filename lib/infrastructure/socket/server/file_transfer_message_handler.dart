import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/remote_file_entry.dart';
import 'package:backup_database/domain/services/i_file_transfer_lock_service.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/file_chunker.dart';
import 'package:backup_database/infrastructure/protocol/file_transfer_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:path/path.dart' as p;

typedef SendToClient = Future<void> Function(String clientId, Message message);

class FileTransferMessageHandler {
  FileTransferMessageHandler({
    required String allowedBasePath,
    required IFileTransferLockService lockService,
    FileChunker? chunker,
  })  : _allowedBasePath = p.normalize(p.absolute(allowedBasePath)),
        _lockService = lockService,
        _chunker = chunker ?? FileChunker();

  final String _allowedBasePath;
  final IFileTransferLockService _lockService;
  final FileChunker _chunker;

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

    // Adquire lock para evitar conflitos de download simultâneo
    final lockAcquired = await _lockService.tryAcquireLock(filePath);
    if (!lockAcquired) {
      await sendToClient(
        clientId,
        createFileTransferErrorMessage(
          requestId: requestId,
          errorMessage: 'Arquivo está sendo baixado por outro cliente. Tente novamente em alguns minutos.',
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

      final file = File(resolved);
      if (!await file.exists()) {
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

      final fileName = p.basename(resolved);
      final fileSize = await file.length();
      final chunks = await _chunker.chunkFile(resolved);
      final totalChunks = chunks.length;

      await sendToClient(
        clientId,
        createFileTransferStartMetadataMessage(
          requestId: requestId,
          fileName: fileName,
          fileSize: fileSize,
          totalChunks: totalChunks,
        ),
      );

      for (var i = 0; i < chunks.length; i++) {
        await sendToClient(
          clientId,
          createFileChunkMessage(requestId: requestId, chunk: chunks[i]),
        );
        await sendToClient(
          clientId,
          createFileTransferProgressMessage(
            requestId: requestId,
            currentChunk: i + 1,
            totalChunks: totalChunks,
          ),
        );
      }

      await sendToClient(
        clientId,
        createFileTransferCompleteMessage(requestId: requestId),
      );
      LoggerService.info(
        'File transfer completed: $fileName to client $clientId',
      );
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
        result.add(RemoteFileEntry(
          path: relativePath,
          size: stat.size,
          lastModified: stat.modified,
        ));
      } else if (entity is Directory) {
        result.addAll(
          await _listFilesRecursive(entity, basePath),
        );
      }
    }
    return result;
  }
}
