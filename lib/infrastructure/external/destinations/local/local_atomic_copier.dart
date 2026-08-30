import 'dart:io';

import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';

class LocalAtomicCopier {
  const LocalAtomicCopier();

  Future<void> copyWithRetry({
    required File sourceFile,
    required String destinationPath,
    UploadProgressCallback? onProgress,
  }) async {
    const maxRetries = 3;
    var attempt = 0;
    Object? lastError;

    while (attempt < maxRetries) {
      attempt++;
      try {
        if (attempt > 1) {
          LoggerService.info(
            'Tentativa de cópia $attempt/$maxRetries para $destinationPath...',
          );

          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }

        await _copy(
          sourceFile: sourceFile,
          destinationPath: destinationPath,
          onProgress: onProgress,
        );
        return;
      } on Object catch (e) {
        lastError = e;
        LoggerService.warning(
          'Falha na tentativa $attempt/$maxRetries de copiar arquivo: $e',
        );

        if (e is FileSystemException && (e.osError?.errorCode == 5)) {
          rethrow;
        }
      }
    }

    if (lastError is Exception) throw lastError;
    if (lastError is Error) throw lastError;
    throw FileSystemException(
      'Falha ao copiar arquivo após $maxRetries tentativas',
      destinationPath,
    );
  }

  Future<void> _copy({
    required File sourceFile,
    required String destinationPath,
    UploadProgressCallback? onProgress,
  }) async {
    final tempDestinationPath = '$destinationPath.tmp';
    final tempFile = File(tempDestinationPath);
    final finalFile = File(destinationPath);

    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } on Object catch (e) {
        LoggerService.warning(
          'Não foi possível limpar arquivo temporário antigo: $tempDestinationPath',
          e,
        );
      }
    }

    final sourceSize = await sourceFile.length();

    try {
      await sourceFile.copyToWithBugFix(
        tempDestinationPath,
        onProgress: onProgress,
      );

      final tempSize = await tempFile.length();
      if (tempSize != sourceSize) {
        throw FileSystemException(
          'Tamanho do arquivo temporário incorreto. '
          'Esperado: $sourceSize, Encontrado: $tempSize',
          tempDestinationPath,
        );
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(destinationPath);
    } on Object catch (e) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } on Object catch (_) {}
      }
      rethrow;
    }
  }
}

extension FileCopyWithProgress on File {
  static int get _chunkSize => UploadChunkConstants.localCopyChunkSize;

  Future<void> copyToWithBugFix(
    String newPath, {
    UploadProgressCallback? onProgress,
  }) async {
    LoggerService.debug(
      '[CopyDebug] Iniciando copyToWithBugFix: $path -> $newPath',
    );

    final sourceRaf = await _openWithRetry();
    RandomAccessFile? destRaf;

    try {
      LoggerService.debug('[CopyDebug] Source aberto. Abrindo destino...');
      destRaf = await File(newPath).open(mode: FileMode.write);
      LoggerService.debug(
        '[CopyDebug] Destino aberto (RAF). Iniciando loop...',
      );

      final fileSize = await sourceRaf.length();
      var bytesCopied = 0;
      var loopCount = 0;

      while (bytesCopied < fileSize) {
        loopCount++;
        final bytesToRead = _chunkSize < (fileSize - bytesCopied)
            ? _chunkSize
            : (fileSize - bytesCopied);
        final buffer = List<int>.filled(bytesToRead, 0);

        final bytesRead = await sourceRaf.readInto(buffer, 0, bytesToRead);

        if (bytesRead == 0 && bytesToRead > 0) {
          throw FileSystemException(
            'Leitura interrompida inesperadamente (0 bytes lidos) na posição $bytesCopied',
            newPath,
          );
        }

        if (bytesRead < bytesToRead) {
          await destRaf.writeFrom(buffer, 0, bytesRead);
          bytesCopied += bytesRead;
        } else {
          await destRaf.writeFrom(buffer);
          bytesCopied += bytesToRead;
        }

        if (loopCount % 10 == 0 || bytesCopied == fileSize) {
          LoggerService.debug(
            '[CopyDebug] Loop $loopCount: $bytesCopied/$fileSize bytes copiados',
          );
        }

        if (onProgress != null && fileSize > 0) {
          final progress = bytesCopied / fileSize;
          onProgress(progress);
        }
      }
      LoggerService.debug('[CopyDebug] Loop finalizado. Efetuando flush...');
      await destRaf.flush();
      LoggerService.debug('[CopyDebug] Flush OK.');
    } on Object catch (e, st) {
      LoggerService.error('[CopyDebug] Erro durante cópia: $e', e, st);
      rethrow;
    } finally {
      LoggerService.debug('[CopyDebug] Fechando arquivos...');
      try {
        await sourceRaf.close();
        LoggerService.debug('[CopyDebug] Source fechado.');
      } on Object catch (e) {
        LoggerService.warning('[CopyDebug] Erro ao fechar source: $e');
      }
      try {
        await destRaf?.close();
        LoggerService.debug('[CopyDebug] Destino fechado.');
      } on Object catch (e) {
        LoggerService.warning('[CopyDebug] Erro ao fechar destino: $e');
      }
    }
  }

  Future<RandomAccessFile> _openWithRetry([int retries = 3]) async {
    var attempt = 0;
    while (true) {
      try {
        attempt++;
        return await open();
      } catch (e) {
        if (attempt >= retries) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }
}
