import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_local_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class LocalDestinationService implements ILocalDestinationService {
  @override
  Future<rd.Result<LocalUploadResult>> upload({
    required String sourceFilePath,
    required LocalDestinationConfig config,
    String? customFileName,
    UploadProgressCallback? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      LoggerService.info('Copiando para destino local: ${config.path}');

      final sourceFile = File(sourceFilePath);
      if (!await sourceFile.exists()) {
        return rd.Failure(
          FileSystemFailure(
            message: 'Arquivo de origem não encontrado: $sourceFilePath',
          ),
        );
      }

      final sizeValidation = await _validateSourceFileWithRetry(sourceFile);
      if (sizeValidation.isError()) {
        final error = sizeValidation.exceptionOrNull();
        final message = error is Failure
            ? error.message
            : error?.toString() ?? 'Erro desconhecido';
        return rd.Failure(
          FileSystemFailure(
            message:
                'Arquivo de origem inválido: $sourceFilePath\n'
                'O arquivo pode estar ainda sendo baixado ou travado pelo sistema.\n'
                'Detalhes: $message',
          ),
        );
      }

      var destinationDir = config.path;
      if (config.createSubfoldersByDate) {
        final dateFolder = DateFormat('yyyy-MM-dd').format(DateTime.now());
        destinationDir = p.join(config.path, dateFolder);
      }

      final directory = Directory(destinationDir);
      try {
        if (!await directory.exists()) {
          await directory.create(recursive: true);
          LoggerService.debug('Diretório criado: $destinationDir');
        }
      } on FileSystemException catch (e) {
        stopwatch.stop();
        final errorMessage = _getPermissionErrorMessage(e, destinationDir);
        LoggerService.error('Erro ao criar diretório', e);
        return rd.Failure(
          FileSystemFailure(
            message: errorMessage,
            originalError: e,
          ),
        );
      }

      final canWrite = await _checkWritePermission(destinationDir);
      if (!canWrite) {
        stopwatch.stop();
        return rd.Failure(
          FileSystemFailure(
            message:
                'Sem permissão de escrita no diretório: $destinationDir\n'
                'Verifique as permissões ou escolha outro diretório.',
          ),
        );
      }

      final fileName = customFileName ?? p.basename(sourceFilePath);
      final destinationPath = p.join(destinationDir, fileName);

      try {
        final normalizedSource = p.normalize(p.absolute(sourceFilePath));
        final normalizedDest = p.normalize(p.absolute(destinationPath));
        final samePath =
            normalizedSource.toLowerCase() == normalizedDest.toLowerCase();
        if (samePath) {
          stopwatch.stop();
          LoggerService.warning(
            'Origem e destino são o mesmo arquivo (pasta temp = pasta final). '
            'Configure um destino final diferente da pasta temp.',
          );
          return const rd.Failure(
            FileSystemFailure(
              message:
                  'O destino final não pode ser a mesma pasta do arquivo temporário. '
                  'Configure em "Destinos" um caminho final diferente da pasta temp '
                  r'(ex.: temp = C:\Temp, destino final = D:\Backups).',
            ),
          );
        }

        LoggerService.info(
          'Iniciando cópia: $sourceFilePath -> $destinationPath',
        );

        final sourceFile = File(sourceFilePath);
        if (!await sourceFile.exists()) {
          throw FileSystemException(
            sourceFilePath,
            'Arquivo de origem não encontrado',
          );
        }

        final destinationFile = File(destinationPath);
        if (await destinationFile.exists()) {
          LoggerService.info('Arquivo de destino já existe, será sobrescrito');
          try {
            await destinationFile.delete();
            LoggerService.info('Arquivo de destino antigo removido');
          } on Object catch (e) {
            throw FileSystemException(
              destinationPath,
              'Não foi possível remover arquivo existente: $e',
            );
          }
        }

        LoggerService.info(
          'Executando cópia segura: $sourceFilePath -> $destinationPath',
        );

        await _atomicCopyWithRetry(
          sourceFile: sourceFile,
          destinationPath: destinationPath,
          onProgress: onProgress,
        );

        LoggerService.info('Cópia atômica concluída com sucesso');

        stopwatch.stop();

        if (!await destinationFile.exists()) {
          throw FileSystemException(
            destinationPath,
            'Arquivo de destino não encontrado após cópia atômica',
          );
        }

        final copiedSize = await destinationFile.length();
        final sourceSize = await sourceFile.length();
        LoggerService.info('Tamanho do arquivo de origem: $sourceSize bytes');
        LoggerService.info('Tamanho do arquivo de destino: $copiedSize bytes');

        if (copiedSize != sourceSize) {
          throw FileSystemException(
            destinationPath,
            'Tamanho do arquivo de destino difere do arquivo de origem após cópia '
            '(origem: $sourceSize bytes, destino: $copiedSize bytes)',
          );
        }

        LoggerService.info(
          'Arquivo copiado com sucesso: $destinationPath ($copiedSize bytes)',
        );

        onProgress?.call(1);

        return rd.Success(
          LocalUploadResult(
            destinationPath: destinationPath,
            fileSize: copiedSize,
            duration: stopwatch.elapsed,
          ),
        );
      } on FileSystemException catch (e) {
        stopwatch.stop();
        final errorMessage = _getPermissionErrorMessage(e, destinationPath);
        LoggerService.error('Erro ao copiar arquivo', e);
        return rd.Failure(
          FileSystemFailure(
            message: errorMessage,
            originalError: e,
          ),
        );
      }
    } on Object catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('Erro ao copiar para destino local', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message:
              'Erro ao copiar arquivo para destino local: ${_getUserFriendlyError(e)}',
          originalError: e,
        ),
      );
    }
  }

  Future<void> _atomicCopyWithRetry({
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

        await _atomicCopy(
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

  Future<void> _atomicCopy({
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

  Future<bool> _checkWritePermission(String path) async {
    try {
      final testFile = File(
        p.join(path, '.write_test_${DateTime.now().millisecondsSinceEpoch}'),
      );
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } on Object catch (e, stackTrace) {
      LoggerService.debug(
        'Falha ao verificar permissão de escrita em: $path',
        e,
        stackTrace,
      );
      return false;
    }
  }

  Future<rd.Result<int>> _validateSourceFileWithRetry(File sourceFile) async {
    const maxAttempts = 10;
    const initialDelayMs = 100;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final size = await sourceFile.length();

        if (size > 0) {
          if (attempt > 0) {
            LoggerService.info(
              '[ValidateFile] Arquivo válido na tentativa ${attempt + 1}: $size bytes',
            );
          }
          return rd.Success(size);
        }

        LoggerService.warning(
          '[ValidateFile] Arquivo com 0 bytes na tentativa ${attempt + 1}, '
          'aguardando liberação...',
        );

        if (attempt < maxAttempts - 1) {
          final delay = initialDelayMs * (attempt + 1);
          await Future.delayed(Duration(milliseconds: delay));
        }
      } on FileSystemException catch (e) {
        LoggerService.warning(
          '[ValidateFile] Erro ao ler arquivo (tentativa ${attempt + 1}): $e',
        );

        if (attempt < maxAttempts - 1) {
          final delay = initialDelayMs * (attempt + 1);
          await Future.delayed(Duration(milliseconds: delay));
        } else {
          return rd.Failure(
            FileSystemFailure(
              message:
                  'Arquivo travado ou inacessível após $maxAttempts tentativas',
              originalError: e,
            ),
          );
        }
      } on Object catch (e) {
        LoggerService.error(
          '[ValidateFile] Erro inesperado ao validar arquivo',
          e,
        );
        return rd.Failure(
          FileSystemFailure(
            message: 'Erro inesperado ao validar arquivo: $e',
            originalError: e,
          ),
        );
      }
    }

    return const rd.Failure(
      FileSystemFailure(
        message:
            'Arquivo inválido (0 bytes) após $maxAttempts tentativas. '
            'O arquivo pode estar ainda sendo baixado.',
      ),
    );
  }

  String _getPermissionErrorMessage(FileSystemException e, String path) {
    if (e.osError?.errorCode == 5) {
      return 'Acesso negado ao diretório: $path\n'
          'Execute o aplicativo como Administrador ou escolha outro diretório.';
    } else if (e.osError?.errorCode == 3) {
      return 'Caminho não encontrado: $path\n'
          'Verifique se o disco ou pasta existe.';
    } else if (e.osError?.errorCode == 112) {
      return 'Disco cheio ou sem espaço suficiente: $path';
    }
    return 'Erro ao acessar: $path - ${e.message}';
  }

  String _getUserFriendlyError(dynamic e) {
    if (e is FileSystemException) {
      return _getPermissionErrorMessage(e, e.path ?? 'desconhecido');
    }
    return e.toString();
  }

  @override
  Future<rd.Result<bool>> testConnection(LocalDestinationConfig config) async {
    try {
      final directory = Directory(config.path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final canWrite = await _checkWritePermission(config.path);
      if (!canWrite) {
        return rd.Failure(
          FileSystemFailure(
            message:
                'Sem permissão de escrita no diretório: ${config.path}\n'
                'Verifique as permissões ou escolha outro diretório.',
          ),
        );
      }
      return const rd.Success(true);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao testar conexão com diretório local',
        e,
        stackTrace,
      );
      return rd.Failure(
        FileSystemFailure(
          message: 'Erro ao acessar diretório: ${_getUserFriendlyError(e)}',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<int>> cleanOldBackups({
    required LocalDestinationConfig config,
  }) async {
    try {
      LoggerService.info('Limpando backups antigos em: ${config.path}');

      final directory = Directory(config.path);
      if (!await directory.exists()) {
        return const rd.Success(0);
      }

      final cutoffDate = DateTime.now().subtract(
        Duration(days: config.retentionDays),
      );

      var deletedCount = 0;
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            await entity.delete();
            deletedCount++;
            LoggerService.debug('Arquivo deletado: ${entity.path}');
          }
        }
      }

      await for (final entity in directory.list()) {
        if (entity is Directory) {
          final contents = await entity.list().toList();
          if (contents.isEmpty) {
            await entity.delete();
            LoggerService.debug('Diretório vazio removido: ${entity.path}');
          }
        }
      }

      LoggerService.info('$deletedCount arquivo(s) antigo(s) removido(s)');
      return rd.Success(deletedCount);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao limpar backups antigos', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message: 'Erro ao limpar backups antigos: $e',
          originalError: e,
        ),
      );
    }
  }
}

extension FileCopyWithProgress on File {
  static const int _chunkSize = 1024 * 1024;

  Future<void> copyToWithBugFix(
    String newPath, {
    UploadProgressCallback? onProgress,
  }) async {
    LoggerService.info(
      '[CopyDebug] Iniciando copyToWithBugFix: $path -> $newPath',
    );

    final sourceRaf = await _openWithRetry();
    RandomAccessFile? destRaf;

    try {
      LoggerService.info('[CopyDebug] Source aberto. Abrindo destino...');
      destRaf = await File(newPath).open(mode: FileMode.write);
      LoggerService.info('[CopyDebug] Destino aberto (RAF). Iniciando loop...');

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
      LoggerService.info('[CopyDebug] Loop finalizado. Efetuando flush...');
      await destRaf.flush();
      LoggerService.info('[CopyDebug] Flush OK.');
    } on Object catch (e, st) {
      LoggerService.error('[CopyDebug] Erro durante cópia: $e', e, st);
      rethrow;
    } finally {
      LoggerService.info('[CopyDebug] Fechando arquivos...');
      try {
        await sourceRaf.close();
        LoggerService.info('[CopyDebug] Source fechado.');
      } on Object catch (e) {
        LoggerService.warning('[CopyDebug] Erro ao fechar source: $e');
      }
      try {
        await destRaf?.close();
        LoggerService.info('[CopyDebug] Destino fechado.');
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
