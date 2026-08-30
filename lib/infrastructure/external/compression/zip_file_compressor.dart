import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/directory_permission_check.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/compression_result.dart';
import 'package:backup_database/infrastructure/external/compression/compression_cleanup_retry.dart';
import 'package:backup_database/infrastructure/external/compression/compression_errors.dart';
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
    } on Object catch (_) {
      throw FileSystemException(
        'Não foi possível remover arquivo ZIP existente: $outputFilePath',
        outputFilePath,
      );
    }
  }

  final encoder = ZipFileEncoder();

  try {
    encoder.create(outputFilePath);
    await encoder.addFile(inputFile);

    try {
      await encoder.close();
    } on FileSystemException {
      try {
        final partialZip = File(outputFilePath);
        if (await partialZip.exists()) {
          await partialZip.delete();
        }
      } on Object catch (e, s) {
        LoggerService.warning(
          'Erro ao remover ZIP parcial: $outputFilePath',
          e,
          s,
        );
      }

      rethrow;
    }
  } on Object catch (_) {
    try {
      await encoder.close();
    } on Object catch (closeErr, s) {
      LoggerService.warning('Erro ao fechar encoder em fallback', closeErr, s);
    }
    rethrow;
  }
}

class ZipFileCompressor {
  ZipFileCompressor({CompressionCleanupRetry? cleanup})
    : _cleanup = cleanup ?? const CompressionCleanupRetry();

  final CompressionCleanupRetry _cleanup;

  Future<rd.Result<CompressionResult>> compress({
    required String filePath,
    required String outputFilePath,
    required int originalSize,
    required Stopwatch stopwatch,
    bool deleteOriginal = false,
  }) async {
    LoggerService.info('Usando biblioteca archive para compressão...');

    final inputFile = File(filePath);
    final outputFile = File(outputFilePath);

    if (await outputFile.exists()) {
      LoggerService.warning(
        'Arquivo ZIP já existe, removendo: $outputFilePath',
      );
      try {
        await _cleanup.deleteFileWithRetry(outputFile, outputFilePath);

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

    final hasWritePermission =
        await DirectoryPermissionCheck.hasWritePermission(
          outputDir,
        );
    if (!hasWritePermission) {
      LoggerService.error('Sem permissão de escrita no diretório');
      return rd.Failure(
        FileSystemFailure(
          message:
              'Sem permissão de escrita no diretório: ${outputDir.path}\n'
              'Execute o aplicativo como Administrador ou escolha outro diretório.',
        ),
      );
    }

    try {
      LoggerService.info('Criando arquivo ZIP: $outputFilePath');
      LoggerService.info(
        'Arquivo original: ${ByteFormat.format(originalSize)}',
      );
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
        } on Object catch (delErr, s) {
          LoggerService.warning(
            'Erro ao remover arquivo de saída após falha: $outputFilePath',
            delErr,
            s,
          );
        }

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
        } on Object catch (delErr, s) {
          LoggerService.warning(
            'Erro ao remover arquivo de saída após falha: $outputFilePath',
            delErr,
            s,
          );
        }

        return rd.Failure(
          FileSystemFailure(
            message:
                'Erro ao comprimir arquivo: '
                '${CompressionErrors.userFriendlyError(e)}',
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
          'Arquivo ZIP criado com sucesso: ${ByteFormat.format(createdSize)}',
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
      LoggerService.error('Erro de sistema de arquivos durante compressão', e);

      try {
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
      } on Object catch (delErr, s) {
        LoggerService.warning(
          'Erro ao remover arquivo de saída após falha: $outputFilePath',
          delErr,
          s,
        );
      }

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
          message: CompressionErrors.fileSystemErrorMessage(e),
          originalError: e,
        ),
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro inesperado durante compressão', e, stackTrace);

      try {
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
      } on Object catch (delErr, s) {
        LoggerService.warning(
          'Erro ao remover arquivo de saída após falha: $outputFilePath',
          delErr,
          s,
        );
      }

      return rd.Failure(
        FileSystemFailure(
          message:
              'Erro ao comprimir arquivo: '
              '${CompressionErrors.userFriendlyError(e)}',
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
      'Compressão concluída: ${ByteFormat.format(originalSize)} → ${ByteFormat.format(compressedSize)} '
      '(${compressionRatio.toStringAsFixed(1)}% de redução)',
    );

    if (deleteOriginal) {
      await _cleanup.deleteFileWithRetry(inputFile, filePath);
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
}
