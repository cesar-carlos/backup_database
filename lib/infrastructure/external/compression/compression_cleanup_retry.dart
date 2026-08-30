import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';

class CompressionCleanupRetry {
  const CompressionCleanupRetry();

  static const int _maxRetries = 5;
  static const Duration _initialDelay = Duration(milliseconds: 500);
  static const Duration _retryDelay = Duration(milliseconds: 1000);

  Future<void> deleteFileWithRetry(File file, String filePath) async {
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        if (attempt > 1) {
          await Future.delayed(_retryDelay);
        } else {
          await Future.delayed(_initialDelay);
        }

        await file.delete();
        LoggerService.info('Arquivo original deletado: $filePath');
        return;
      } on FileSystemException catch (e) {
        final errorCode = e.osError?.errorCode;
        if (errorCode == 32) {
          if (attempt < _maxRetries) {
            LoggerService.warning(
              'Arquivo ainda em uso, tentando novamente (tentativa $attempt/$_maxRetries): $filePath',
            );
            continue;
          } else {
            LoggerService.warning(
              'Não foi possível deletar arquivo original após $_maxRetries tentativas. '
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

  Future<void> deleteDirectoryWithRetry(
    Directory directory,
    String directoryPath,
  ) async {
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        if (attempt > 1) {
          await Future.delayed(_retryDelay);
        } else {
          await Future.delayed(_initialDelay);
        }

        await directory.delete(recursive: true);
        LoggerService.info('Diretório original deletado: $directoryPath');
        return;
      } on FileSystemException catch (e) {
        final errorCode = e.osError?.errorCode;
        if (errorCode == 32 || errorCode == 145) {
          if (attempt < _maxRetries) {
            LoggerService.warning(
              'Diretório ainda em uso, tentando novamente (tentativa $attempt/$_maxRetries): $directoryPath',
            );
            continue;
          } else {
            LoggerService.warning(
              'Não foi possível deletar diretório original após $_maxRetries tentativas. '
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
}
