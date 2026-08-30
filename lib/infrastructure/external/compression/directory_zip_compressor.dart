import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/compression_result.dart';
import 'package:backup_database/infrastructure/external/compression/compression_cleanup_retry.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class DirectoryZipCompressor {
  DirectoryZipCompressor({CompressionCleanupRetry? cleanup})
    : _cleanup = cleanup ?? const CompressionCleanupRetry();

  final CompressionCleanupRetry _cleanup;

  Future<rd.Result<CompressionResult>> compress({
    required String directoryPath,
    required String outputFilePath,
    required Stopwatch stopwatch,
    bool deleteOriginal = false,
  }) async {
    LoggerService.info(
      'Usando biblioteca archive para compressão de diretório...',
    );

    final inputDir = Directory(directoryPath);
    var originalSize = 0;

    final outputFile = File(outputFilePath);
    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    final encoder = ZipFileEncoder();
    try {
      encoder.create(outputFilePath);

      await for (final entity in inputDir.list(recursive: true)) {
        if (entity is File) {
          final fileSize = await entity.length();
          originalSize += fileSize;
          final relativePath = p.relative(entity.path, from: directoryPath);
          await encoder.addFile(entity, relativePath);
          LoggerService.debug('Adicionado ao ZIP: $relativePath');
        }
      }

      await encoder.close();
    } on Object catch (_) {
      try {
        await encoder.close();
      } on Object catch (closeErr, s) {
        LoggerService.warning(
          'Erro ao fechar encoder em fallback',
          closeErr,
          s,
        );
      }
      rethrow;
    }

    final compressedSize = await outputFile.length();
    stopwatch.stop();

    final compressionRatio = originalSize > 0
        ? (1 - (compressedSize / originalSize)) * 100
        : 0.0;

    LoggerService.info(
      'Compressão de diretório concluída: ${ByteFormat.format(originalSize)} → ${ByteFormat.format(compressedSize)} '
      '(${compressionRatio.toStringAsFixed(1)}% de redução)',
    );

    if (deleteOriginal) {
      await _cleanup.deleteDirectoryWithRetry(inputDir, directoryPath);
    }

    return rd.Success(
      CompressionResult(
        compressedPath: outputFilePath,
        compressedSize: compressedSize,
        originalSize: originalSize,
        duration: stopwatch.elapsed,
        compressionRatio: compressionRatio,
      ),
    );
  }

  Future<int> calculateDirectorySize(Directory directory) async {
    var totalSize = 0;
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao calcular tamanho do diretório: ${directory.path}',
        e,
      );
    }
    return totalSize;
  }
}
