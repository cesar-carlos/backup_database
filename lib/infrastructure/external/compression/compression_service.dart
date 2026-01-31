import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/services/compression_result.dart';
import 'package:backup_database/domain/services/i_compression_service.dart';
import 'package:backup_database/infrastructure/external/compression/winrar_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

Future<void> compressFileInIsolate(Map<String, String> params) async {
  final inputFilePath = params['inputFilePath']!;
  final outputFilePath = params['outputFilePath']!;

  final inputFile = File(inputFilePath);

  final outputFileBeforeCreate = File(outputFilePath);
  final outputExistsBeforeCreate = await outputFileBeforeCreate.exists();
  if (outputExistsBeforeCreate) {
    try {
      await outputFileBeforeCreate.delete();
      await Future.delayed(const Duration(milliseconds: 200));
    } on Object catch (e) {
      throw FileSystemException(
        'Não foi possível remover arquivo ZIP existente: $outputFilePath',
        outputFilePath,
      );
    }
  }

  final encoder = ZipFileEncoder();

  try {
    encoder.create(outputFilePath);
    encoder.addFile(inputFile);

    try {
      encoder.close();
    } on FileSystemException {
      try {
        final partialZip = File(outputFilePath);
        if (await partialZip.exists()) {
          await partialZip.delete();
        }
      } on Object catch (_) {}

      rethrow;
    }
  } on Object catch (e) {
    try {
      encoder.close();
    } on Object catch (_) {}
    rethrow;
  }
}

class CompressionService implements ICompressionService {
  CompressionService(ProcessService processService)
    : _winRarService = WinRarService(processService);
  final WinRarService _winRarService;

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

      var originalSize = 0;
      var useWinRar = await _winRarService.isAvailable();

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

            originalSize = await _calculateDirectorySize(inputDir);

            if (deleteOriginal) {
              await _deleteDirectoryWithRetry(inputDir, directoryPath);
            }

            final compressionRatio = originalSize > 0
                ? (1 - (compressedSize / originalSize)) * 100
                : 0.0;

            LoggerService.info(
              'Compressão WinRAR concluída: ${_formatBytes(originalSize)} → ${_formatBytes(compressedSize)} '
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
        useWinRar = false;
      }

      LoggerService.info(
        'Usando biblioteca archive para compressão de diretório...',
      );

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
            encoder.addFile(entity, relativePath);
            LoggerService.debug('Adicionado ao ZIP: $relativePath');
          }
        }

        encoder.close();
      } on Object catch (e) {
        try {
          encoder.close();
        } on Object catch (_) {}
        rethrow;
      }

      final compressedSize = await outputFile.length();
      stopwatch.stop();

      final compressionRatio = originalSize > 0
          ? (1 - (compressedSize / originalSize)) * 100
          : 0.0;

      LoggerService.info(
        'Compressão de diretório concluída: ${_formatBytes(originalSize)} → ${_formatBytes(compressedSize)} '
        '(${compressionRatio.toStringAsFixed(1)}% de redução)',
      );

      if (deleteOriginal) {
        await _deleteDirectoryWithRetry(inputDir, directoryPath);
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
    } on Object catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('Erro ao comprimir diretório', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message: 'Erro ao comprimir diretório: ${_getUserFriendlyError(e)}',
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
              await _deleteFileWithRetry(inputFile, filePath);
            }

            final compressionRatio = originalSize > 0
                ? (1 - (compressedSize / originalSize)) * 100
                : 0.0;

            LoggerService.info(
              'Compressão WinRAR concluída: ${_formatBytes(originalSize)} → ${_formatBytes(compressedSize)} '
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

      LoggerService.info('Usando biblioteca archive para compressão...');

      final outputFile = File(outputFilePath);

      if (await outputFile.exists()) {
        LoggerService.warning(
          'Arquivo ZIP já existe, removendo: $outputFilePath',
        );
        try {
          await _deleteFileWithRetry(outputFile, outputFilePath);

          await Future.delayed(const Duration(milliseconds: 500));

          if (await outputFile.exists()) {
            LoggerService.warning(
              'Arquivo ainda existe após tentativa de remoção',
            );
            return rd.Failure(
              FileSystemFailure(
                message:
                    'Arquivo ZIP está em uso e não pode ser removido: $outputFilePath\n'
                    'Feche outros programas que possam estar usando o arquivo.',
              ),
            );
          }
        } on FileSystemException catch (e) {
          LoggerService.error('Erro ao remover arquivo ZIP existente', e);
          if (e.osError?.errorCode == 5) {
            return rd.Failure(
              FileSystemFailure(
                message:
                    'Acesso negado ao remover arquivo ZIP existente: $outputFilePath\n'
                    'O arquivo pode estar em uso por outro processo.\n'
                    'Execute o aplicativo como Administrador ou feche outros programas.',
                originalError: e,
              ),
            );
          }
          return rd.Failure(
            FileSystemFailure(
              message:
                  'Não foi possível remover arquivo ZIP existente: $outputFilePath',
              originalError: e,
            ),
          );
        } on Object catch (e) {
          LoggerService.error('Erro ao remover arquivo ZIP existente', e);
          return rd.Failure(
            FileSystemFailure(
              message:
                  'Não foi possível remover arquivo ZIP existente: $outputFilePath',
              originalError: e,
            ),
          );
        }
      }

      final outputDir = Directory(p.dirname(outputFilePath));
      if (!await outputDir.exists()) {
        try {
          await outputDir.create(recursive: true);
          LoggerService.info('Diretório criado: ${outputDir.path}');
        } on Object catch (e) {
          LoggerService.error('Erro ao criar diretório de saída', e);
          return rd.Failure(
            FileSystemFailure(
              message:
                  'Não foi possível criar diretório: ${outputDir.path}\n'
                  'Verifique as permissões ou execute como Administrador.',
              originalError: e,
            ),
          );
        }
      }

      try {
        final testFile = File(p.join(outputDir.path, '.test_write_permission'));
        await testFile.writeAsString('test');
        await testFile.delete();
      } on Object catch (e) {
        LoggerService.error('Sem permissão de escrita no diretório', e);
        return rd.Failure(
          FileSystemFailure(
            message:
                'Sem permissão de escrita no diretório: ${outputDir.path}\n'
                'Execute o aplicativo como Administrador ou escolha outro diretório.',
            originalError: e,
          ),
        );
      }

      try {
        LoggerService.info('Criando arquivo ZIP: $outputFilePath');
        LoggerService.info('Arquivo original: ${_formatBytes(originalSize)}');
        LoggerService.info(
          'Comprimindo arquivo em background (isso pode levar alguns minutos para arquivos grandes)...',
        );
        LoggerService.info('Arquivo: $filePath');

        try {
          await compute(compressFileInIsolate, {
            'inputFilePath': filePath,
            'outputFilePath': outputFilePath,
          });

          LoggerService.info('Arquivo comprimido com sucesso no isolate');
        } on FileSystemException catch (e) {
          LoggerService.error('Erro ao comprimir arquivo no isolate', e);

          try {
            if (await outputFile.exists()) {
              await outputFile.delete();
            }
          } on Object catch (_) {}

          var errorMessage = 'Erro ao comprimir arquivo: ${e.message}';
          if (e.message.contains('writeFrom failed') ||
              e.message.contains('Acesso negado') ||
              e.osError?.errorCode == 5) {
            errorMessage =
                'Acesso negado ao criar arquivo ZIP: $outputFilePath\n'
                'Possíveis causas:\n'
                '- Arquivo de entrada está em uso por outro processo\n'
                '- Arquivo ZIP de saída está em uso\n'
                '- Sem permissão de escrita no diretório\n'
                '- Execute o aplicativo como Administrador\n'
                '- Escolha outro diretório de destino';
          }

          return rd.Failure(
            FileSystemFailure(message: errorMessage, originalError: e),
          );
        } on Object catch (e) {
          LoggerService.error(
            'Erro inesperado ao comprimir arquivo no isolate',
            e,
          );

          try {
            if (await outputFile.exists()) {
              await outputFile.delete();
            }
          } on Object catch (_) {}

          return rd.Failure(
            FileSystemFailure(
              message: 'Erro ao comprimir arquivo: ${_getUserFriendlyError(e)}',
              originalError: e,
            ),
          );
        }

        LoggerService.info(
          'ZIP fechado com sucesso, verificando arquivo criado...',
        );

        try {
          if (!await outputFile.exists()) {
            return rd.Failure(
              FileSystemFailure(
                message: 'Arquivo ZIP não foi criado: $outputFilePath',
              ),
            );
          }

          final createdSize = await outputFile.length();
          if (createdSize == 0) {
            return rd.Failure(
              FileSystemFailure(
                message: 'Arquivo ZIP criado está vazio: $outputFilePath',
              ),
            );
          }

          LoggerService.info(
            'Arquivo ZIP criado com sucesso: ${_formatBytes(createdSize)}',
          );
        } on FileSystemException catch (e) {
          LoggerService.error('Erro ao verificar arquivo ZIP criado', e);
          return rd.Failure(
            FileSystemFailure(
              message: 'Erro ao verificar arquivo ZIP: ${e.message}',
              originalError: e,
            ),
          );
        }
      } on FileSystemException catch (e) {
        LoggerService.error(
          'Erro de sistema de arquivos durante compressão',
          e,
        );

        try {
          if (await outputFile.exists()) {
            await outputFile.delete();
          }
        } on Object catch (_) {}

        final errorCode = e.osError?.errorCode;
        if (errorCode == 5) {
          return rd.Failure(
            FileSystemFailure(
              message:
                  'Acesso negado ao criar arquivo ZIP: $outputFilePath\n'
                  'Possíveis causas:\n'
                  '- O arquivo está sendo usado por outro processo\n'
                  '- Sem permissão de escrita no diretório\n'
                  '- Execute o aplicativo como Administrador\n'
                  '- Escolha outro diretório de destino',
              originalError: e,
            ),
          );
        }

        return rd.Failure(
          FileSystemFailure(
            message: _getFileSystemErrorMessage(e),
            originalError: e,
          ),
        );
      } on Object catch (e, stackTrace) {
        LoggerService.error(
          'Erro inesperado durante compressão',
          e,
          stackTrace,
        );

        try {
          if (await outputFile.exists()) {
            await outputFile.delete();
          }
        } on Object catch (_) {}

        return rd.Failure(
          FileSystemFailure(
            message: 'Erro ao comprimir arquivo: ${_getUserFriendlyError(e)}',
            originalError: e,
          ),
        );
      }

      final compressedSize = await outputFile.length();
      stopwatch.stop();

      final compressionRatio = originalSize > 0
          ? (1 - (compressedSize / originalSize)) * 100
          : 0.0;

      LoggerService.info(
        'Compressão concluída: ${_formatBytes(originalSize)} → ${_formatBytes(compressedSize)} '
        '(${compressionRatio.toStringAsFixed(1)}% de redução)',
      );

      if (deleteOriginal) {
        await _deleteFileWithRetry(inputFile, filePath);
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
    } on FileSystemException catch (e) {
      stopwatch.stop();
      LoggerService.error('Erro de sistema de arquivos ao comprimir', e);
      return rd.Failure(
        FileSystemFailure(
          message: _getFileSystemErrorMessage(e),
          originalError: e,
        ),
      );
    } on Object catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('Erro ao comprimir arquivo', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message: 'Erro ao comprimir arquivo: ${_getUserFriendlyError(e)}',
          originalError: e,
        ),
      );
    }
  }

  String _getFileSystemErrorMessage(FileSystemException e) {
    final path = e.path ?? 'desconhecido';
    if (e.osError?.errorCode == 5) {
      return 'Acesso negado ao arquivo: $path\n'
          'Execute o aplicativo como Administrador ou escolha outro diretório.';
    } else if (e.osError?.errorCode == 3) {
      return 'Caminho não encontrado: $path\n'
          'Verifique se o disco ou pasta existe.';
    } else if (e.osError?.errorCode == 112) {
      return 'Disco cheio ou sem espaço suficiente para criar o arquivo ZIP.';
    } else if (e.osError?.errorCode == 32) {
      return 'Arquivo em uso por outro processo: $path\n'
          'O arquivo pode estar sendo usado pelo sistema ou outro programa.\n'
          'Aguarde alguns segundos e tente novamente, ou feche outros programas que podem estar usando o arquivo.';
    }
    return 'Erro ao acessar arquivo: ${e.message}';
  }

  String _getUserFriendlyError(dynamic e) {
    if (e is FileSystemException) {
      return _getFileSystemErrorMessage(e);
    }
    return e.toString();
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

  Future<int> _calculateDirectorySize(Directory directory) async {
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

  Future<void> _deleteFileWithRetry(File file, String filePath) async {
    const maxRetries = 5;
    const initialDelay = Duration(milliseconds: 500);
    const retryDelay = Duration(milliseconds: 1000);

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 1) {
          await Future.delayed(retryDelay);
        } else {
          await Future.delayed(initialDelay);
        }

        await file.delete();
        LoggerService.info('Arquivo original deletado: $filePath');
        return;
      } on FileSystemException catch (e) {
        final errorCode = e.osError?.errorCode;
        if (errorCode == 32) {
          if (attempt < maxRetries) {
            LoggerService.warning(
              'Arquivo ainda em uso, tentando novamente (tentativa $attempt/$maxRetries): $filePath',
            );
            continue;
          } else {
            LoggerService.warning(
              'Não foi possível deletar arquivo original após $maxRetries tentativas. '
              'Arquivo pode estar em uso por outro processo: $filePath',
            );
            return;
          }
        } else {
          LoggerService.warning(
            'Erro ao deletar arquivo original: ${e.message}',
          );
          return;
        }
      } on Object catch (e) {
        LoggerService.warning(
          'Erro inesperado ao deletar arquivo original: $e',
        );
        return;
      }
    }
  }

  Future<void> _deleteDirectoryWithRetry(
    Directory directory,
    String directoryPath,
  ) async {
    const maxRetries = 5;
    const initialDelay = Duration(milliseconds: 500);
    const retryDelay = Duration(milliseconds: 1000);

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 1) {
          await Future.delayed(retryDelay);
        } else {
          await Future.delayed(initialDelay);
        }

        await directory.delete(recursive: true);
        LoggerService.info('Diretório original deletado: $directoryPath');
        return;
      } on FileSystemException catch (e) {
        final errorCode = e.osError?.errorCode;
        if (errorCode == 32 || errorCode == 145) {
          if (attempt < maxRetries) {
            LoggerService.warning(
              'Diretório ainda em uso, tentando novamente (tentativa $attempt/$maxRetries): $directoryPath',
            );
            continue;
          } else {
            LoggerService.warning(
              'Não foi possível deletar diretório original após $maxRetries tentativas. '
              'Diretório pode estar em uso por outro processo: $directoryPath',
            );
            return;
          }
        } else {
          LoggerService.warning(
            'Erro ao deletar diretório original: ${e.message}',
          );
          return;
        }
      } on Object catch (e) {
        LoggerService.warning(
          'Erro inesperado ao deletar diretório original: $e',
        );
        return;
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
