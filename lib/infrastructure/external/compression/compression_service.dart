import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/services/compression_result.dart';
import 'package:backup_database/domain/services/i_compression_service.dart';
import 'package:backup_database/infrastructure/external/compression/compression_cleanup_retry.dart';
import 'package:backup_database/infrastructure/external/compression/compression_errors.dart';
import 'package:backup_database/infrastructure/external/compression/directory_zip_compressor.dart';
import 'package:backup_database/infrastructure/external/compression/winrar_service.dart';
import 'package:backup_database/infrastructure/external/compression/zip_file_compressor.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

export 'zip_file_compressor.dart' show compressFileInIsolate;

class CompressionService implements ICompressionService {
  CompressionService(ProcessService processService)
    : _winRarService = WinRarService(processService);
  final WinRarService _winRarService;
  final CompressionCleanupRetry _cleanup = const CompressionCleanupRetry();
  late final ZipFileCompressor _zipFileCompressor = ZipFileCompressor(
    cleanup: _cleanup,
  );
  late final DirectoryZipCompressor _directoryZipCompressor =
      DirectoryZipCompressor(cleanup: _cleanup);

  @override
  Future<rd.Result<CompressionResult>> compress({
    required String path,
    String? outputPath,
    bool deleteOriginal = false,
    CompressionFormat? format,
  }) async {
    final effectiveFormat = format ?? CompressionFormat.zip;

    if (effectiveFormat == CompressionFormat.none) {
      return const rd.Failure(
        FileSystemFailure(message: 'Compressão desabilitada (formato: none)'),
      );
    }

    final dir = Directory(path);
    if (await dir.exists()) {
      return _compressDirectory(
        directoryPath: path,
        outputPath: outputPath,
        deleteOriginal: deleteOriginal,
        format: effectiveFormat,
      );
    }

    return _compressFile(
      filePath: path,
      outputPath: outputPath,
      deleteOriginal: deleteOriginal,
      format: effectiveFormat,
    );
  }

  Future<rd.Result<CompressionResult>> _compressDirectory({
    required String directoryPath,
    String? outputPath,
    bool deleteOriginal = false,
    CompressionFormat format = CompressionFormat.zip,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      LoggerService.info('Iniciando compressão de diretório: $directoryPath');

      final inputDir = Directory(directoryPath);
      if (!await inputDir.exists()) {
        return rd.Failure(
          FileSystemFailure(
            message: 'Diretório não encontrado: $directoryPath',
          ),
        );
      }

      final extension = format == CompressionFormat.rar ? '.rar' : '.zip';
      final outputFilePath = outputPath ?? '$directoryPath$extension';

      final useWinRar = await _winRarService.isAvailable();

      if (format == CompressionFormat.rar && !useWinRar) {
        return const rd.Failure(
          FileSystemFailure(
            message:
                'Formato RAR requer WinRAR instalado.\n'
                'WinRAR não foi encontrado no sistema.\n'
                'Por favor, instale o WinRAR ou escolha o formato ZIP.',
          ),
        );
      }

      if (useWinRar) {
        LoggerService.info('Tentando comprimir diretório com WinRAR...');
        final winRarSuccess = await _winRarService.compressDirectory(
          directoryPath: directoryPath,
          outputPath: outputFilePath,
          format: format,
        );

        if (winRarSuccess) {
          final outputFile = File(outputFilePath);
          if (await outputFile.exists()) {
            final compressedSize = await outputFile.length();
            stopwatch.stop();

            final originalSize = await _directoryZipCompressor
                .calculateDirectorySize(inputDir);

            if (deleteOriginal) {
              await _cleanup.deleteDirectoryWithRetry(inputDir, directoryPath);
            }

            final compressionRatio = originalSize > 0
                ? (1 - (compressedSize / originalSize)) * 100
                : 0.0;

            LoggerService.info(
              'Compressão WinRAR concluída: ${ByteFormat.format(originalSize)} → ${ByteFormat.format(compressedSize)} '
              '(${compressionRatio.toStringAsFixed(1)}% de redução)',
            );

            return rd.Success(
              CompressionResult(
                compressedPath: outputFilePath,
                compressedSize: compressedSize,
                originalSize: originalSize,
                duration: stopwatch.elapsed,
                compressionRatio: compressionRatio,
                usedWinRar: true,
              ),
            );
          }
        }

        LoggerService.warning('WinRAR falhou, tentando biblioteca archive...');
      }

      return _directoryZipCompressor.compress(
        directoryPath: directoryPath,
        outputFilePath: outputFilePath,
        stopwatch: stopwatch,
        deleteOriginal: deleteOriginal,
      );
    } on Object catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('Erro ao comprimir diretório', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message:
              'Erro ao comprimir diretório: '
              '${CompressionErrors.userFriendlyError(e)}',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<CompressionResult>> _compressFile({
    required String filePath,
    String? outputPath,
    bool deleteOriginal = false,
    CompressionFormat format = CompressionFormat.zip,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      LoggerService.info('Iniciando compressão: $filePath');

      final inputFile = File(filePath);
      if (!await inputFile.exists()) {
        return rd.Failure(
          FileSystemFailure(message: 'Arquivo não encontrado: $filePath'),
        );
      }

      final originalSize = await inputFile.length();
      final extension = format == CompressionFormat.rar ? '.rar' : '.zip';
      final outputFilePath = outputPath ?? '$filePath$extension';

      final winRarAvailable = await _winRarService.isAvailable();

      if (format == CompressionFormat.rar && !winRarAvailable) {
        return const rd.Failure(
          FileSystemFailure(
            message:
                'Formato RAR requer WinRAR instalado.\n'
                'WinRAR não foi encontrado no sistema.\n'
                'Por favor, instale o WinRAR ou escolha o formato ZIP.',
          ),
        );
      }

      if (winRarAvailable) {
        LoggerService.info('Tentando comprimir com WinRAR...');
        final winRarSuccess = await _winRarService.compressFile(
          filePath: filePath,
          outputPath: outputFilePath,
          format: format,
        );

        if (winRarSuccess) {
          final outputFile = File(outputFilePath);
          if (await outputFile.exists()) {
            final compressedSize = await outputFile.length();
            stopwatch.stop();

            if (deleteOriginal) {
              await _cleanup.deleteFileWithRetry(inputFile, filePath);
            }

            final compressionRatio = originalSize > 0
                ? (1 - (compressedSize / originalSize)) * 100
                : 0.0;

            LoggerService.info(
              'Compressão WinRAR concluída: ${ByteFormat.format(originalSize)} → ${ByteFormat.format(compressedSize)} '
              '(${compressionRatio.toStringAsFixed(1)}% de redução)',
            );

            return rd.Success(
              CompressionResult(
                compressedPath: outputFilePath,
                compressedSize: compressedSize,
                originalSize: originalSize,
                duration: stopwatch.elapsed,
                compressionRatio: compressionRatio,
                usedWinRar: true,
              ),
            );
          }
        }

        LoggerService.warning('WinRAR falhou, tentando biblioteca archive...');
      }

      return _zipFileCompressor.compress(
        filePath: filePath,
        outputFilePath: outputFilePath,
        originalSize: originalSize,
        stopwatch: stopwatch,
        deleteOriginal: deleteOriginal,
      );
    } on FileSystemException catch (e) {
      stopwatch.stop();
      LoggerService.error('Erro de sistema de arquivos ao comprimir', e);
      return rd.Failure(
        FileSystemFailure(
          message: CompressionErrors.fileSystemErrorMessage(e),
          originalError: e,
        ),
      );
    } on Object catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('Erro ao comprimir arquivo', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message:
              'Erro ao comprimir arquivo: '
              '${CompressionErrors.userFriendlyError(e)}',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<String>> decompressFile({
    required String zipPath,
    String? outputDirectory,
  }) async {
    try {
      LoggerService.info('Descomprimindo: $zipPath');

      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return rd.Failure(
          FileSystemFailure(message: 'Arquivo ZIP não encontrado: $zipPath'),
        );
      }

      final outputDir = outputDirectory ?? p.dirname(zipPath);
      final targetDir = Directory(outputDir);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      String? extractedFilePath;
      for (final file in archive) {
        final filename = file.name;
        final outputPath = p.join(outputDir, filename);

        if (file.isFile) {
          final data = file.content as List<int>;
          final outputFile = File(outputPath);
          await outputFile.create(recursive: true);
          await outputFile.writeAsBytes(data);
          extractedFilePath = outputPath;
          LoggerService.info('Arquivo extraído: $outputPath');
        } else {
          final dir = Directory(outputPath);
          await dir.create(recursive: true);
        }
      }

      if (extractedFilePath == null) {
        return const rd.Failure(
          FileSystemFailure(message: 'Nenhum arquivo foi extraído do ZIP'),
        );
      }

      LoggerService.info('Descompressão concluída: $extractedFilePath');
      return rd.Success(extractedFilePath);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao descomprimir arquivo', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message: 'Erro ao descomprimir arquivo: $e',
          originalError: e,
        ),
      );
    }
  }
}
