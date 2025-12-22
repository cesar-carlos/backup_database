import 'dart:io';

import 'package:result_dart/result_dart.dart' as rd;
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/services/compression_result.dart';
import '../../../domain/services/i_compression_service.dart';
import '../process/process_service.dart';
import 'winrar_service.dart';

class CompressionService implements ICompressionService {
  final WinRarService _winRarService;

  CompressionService(ProcessService processService)
    : _winRarService = WinRarService(processService);

  @override
  Future<rd.Result<CompressionResult>> compress({
    required String path,
    String? outputPath,
    bool deleteOriginal = false,
  }) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      return _compressDirectory(
        directoryPath: path,
        outputPath: outputPath,
        deleteOriginal: deleteOriginal,
      );
    }

    return _compressFile(
      filePath: path,
      outputPath: outputPath,
      deleteOriginal: deleteOriginal,
    );
  }

  Future<rd.Result<CompressionResult>> _compressDirectory({
    required String directoryPath,
    String? outputPath,
    bool deleteOriginal = false,
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

      final outputFilePath = outputPath ?? '$directoryPath.zip';

      int originalSize = 0;
      bool useWinRar = await _winRarService.isAvailable();

      if (useWinRar) {
        LoggerService.info('Tentando comprimir diretório com WinRAR...');
        final winRarSuccess = await _winRarService.compressDirectory(
          directoryPath: directoryPath,
          outputPath: outputFilePath,
        );

        if (winRarSuccess) {
          final outputFile = File(outputFilePath);
          if (await outputFile.exists()) {
            final compressedSize = await outputFile.length();
            stopwatch.stop();

            originalSize = await _calculateDirectorySize(inputDir);

            if (deleteOriginal) {
              try {
                await inputDir.delete(recursive: true);
                LoggerService.info(
                  'Diretório original deletado: $directoryPath',
                );
              } catch (e) {
                LoggerService.warning('Erro ao deletar diretório original', e);
              }
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
      } catch (e) {
        try {
          encoder.close();
        } catch (_) {}
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
        await inputDir.delete(recursive: true);
        LoggerService.info('Diretório original deletado: $directoryPath');
      }

      return rd.Success(
        CompressionResult(
          compressedPath: outputFilePath,
          compressedSize: compressedSize,
          originalSize: originalSize,
          duration: stopwatch.elapsed,
          compressionRatio: compressionRatio,
          usedWinRar: false,
        ),
      );
    } catch (e, stackTrace) {
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
      final outputFilePath = outputPath ?? '$filePath.zip';

      if (await _winRarService.isAvailable()) {
        LoggerService.info('Tentando comprimir com WinRAR...');
        final winRarSuccess = await _winRarService.compressFile(
          filePath: filePath,
          outputPath: outputFilePath,
        );

        if (winRarSuccess) {
          final outputFile = File(outputFilePath);
          if (await outputFile.exists()) {
            final compressedSize = await outputFile.length();
            stopwatch.stop();

            if (deleteOriginal) {
              try {
                await inputFile.delete();
                LoggerService.info('Arquivo original deletado: $filePath');
              } catch (e) {
                LoggerService.warning('Erro ao deletar arquivo original', e);
              }
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
          await outputFile.delete();

          await Future.delayed(const Duration(milliseconds: 100));

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
        } catch (e) {
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
        } catch (e) {
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
      } catch (e) {
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

      ZipFileEncoder? encoder;
      try {
        LoggerService.info('Criando arquivo ZIP: $outputFilePath');
        LoggerService.info('Arquivo original: ${_formatBytes(originalSize)}');

        encoder = ZipFileEncoder();
        LoggerService.info('Inicializando encoder ZIP...');

        try {
          encoder.create(outputFilePath);
          LoggerService.info('Arquivo ZIP criado, adicionando arquivo...');
        } on FileSystemException catch (e) {
          encoder = null;
          LoggerService.error('Erro ao criar arquivo ZIP', e);
          return rd.Failure(
            FileSystemFailure(
              message:
                  'Acesso negado ao criar arquivo ZIP: $outputFilePath\n'
                  'Possíveis causas:\n'
                  '- Sem permissão de escrita no diretório\n'
                  '- Execute o aplicativo como Administrador\n'
                  '- Escolha outro diretório de destino',
              originalError: e,
            ),
          );
        }

        LoggerService.info(
          'Adicionando arquivo ao ZIP (isso pode levar alguns minutos para arquivos grandes)...',
        );
        LoggerService.info('Arquivo: $filePath');

        try {
          encoder.addFile(inputFile);
          LoggerService.info('Arquivo adicionado ao ZIP');
        } on FileSystemException catch (e) {
          encoder = null;
          LoggerService.error('Erro ao adicionar arquivo ao ZIP', e);

          try {
            if (await outputFile.exists()) {
              await outputFile.delete();
            }
          } catch (_) {}

          String errorMessage =
              'Erro ao adicionar arquivo ao ZIP: ${e.message}';
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
        }

        LoggerService.info(
          'Finalizando criação do ZIP (isso pode levar alguns minutos)...',
        );

        FileSystemException? closeException;
        Object? closeError;
        try {
          encoder.close();
          LoggerService.info('Método close() executado');
        } on FileSystemException catch (e) {
          closeException = e;
          closeError = e;
          LoggerService.error('FileSystemException ao fechar arquivo ZIP', e);
        } catch (e) {
          closeError = e;
          LoggerService.error('Erro ao fechar arquivo ZIP', e);
        } finally {
          encoder = null;
        }

        if (closeException != null) {
          LoggerService.error(
            'Erro ao fechar arquivo ZIP (permissão negada)',
            closeException,
          );

          try {
            if (await outputFile.exists()) {
              await outputFile.delete();
              LoggerService.info('Arquivo ZIP parcial removido');
            }
          } catch (_) {}

          return rd.Failure(
            FileSystemFailure(
              message:
                  'Acesso negado ao finalizar arquivo ZIP: $outputFilePath\n'
                  'Possíveis causas:\n'
                  '- O arquivo está sendo usado por outro processo\n'
                  '- Sem permissão de escrita no diretório\n'
                  '- Execute o aplicativo como Administrador\n'
                  '- Escolha outro diretório de destino',
              originalError: closeException,
            ),
          );
        }

        if (closeError != null) {
          LoggerService.error(
            'Erro inesperado ao fechar arquivo ZIP',
            closeError,
          );

          try {
            if (await outputFile.exists()) {
              await outputFile.delete();
            }
          } catch (_) {}

          return rd.Failure(
            FileSystemFailure(
              message: 'Erro ao finalizar arquivo ZIP: $closeError',
              originalError: closeError,
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
        if (encoder != null) {
          try {
            encoder.close();
          } catch (_) {}
        }

        try {
          if (await outputFile.exists()) {
            await outputFile.delete();
          }
        } catch (_) {}

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
      } catch (e, stackTrace) {
        LoggerService.error(
          'Erro inesperado durante compressão',
          e,
          stackTrace,
        );
        if (encoder != null) {
          try {
            encoder.close();
          } catch (_) {}
        }

        try {
          if (await outputFile.exists()) {
            await outputFile.delete();
          }
        } catch (_) {}

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
        await inputFile.delete();
        LoggerService.info('Arquivo original deletado: $filePath');
      }

      return rd.Success(
        CompressionResult(
          compressedPath: outputFilePath,
          compressedSize: compressedSize,
          originalSize: originalSize,
          duration: stopwatch.elapsed,
          compressionRatio: compressionRatio,
          usedWinRar: false,
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
    } catch (e, stackTrace) {
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
          'Feche outros programas que podem estar usando o arquivo.';
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
    } catch (e, stackTrace) {
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
    int totalSize = 0;
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    } catch (e) {
      LoggerService.warning(
        'Erro ao calcular tamanho do diretório: ${directory.path}',
        e,
      );
    }
    return totalSize;
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
