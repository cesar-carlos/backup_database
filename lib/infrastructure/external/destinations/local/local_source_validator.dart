import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class LocalSourceValidator {
  const LocalSourceValidator();

  Future<rd.Result<int>> validateWithRetry(File sourceFile) async {
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
}
