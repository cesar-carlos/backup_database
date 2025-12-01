import 'dart:io';

import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';

class BackupValidationResult {
  final bool isValid;
  final int fileSize;
  final DateTime lastModified;
  final String? error;

  const BackupValidationResult({
    required this.isValid,
    required this.fileSize,
    required this.lastModified,
    this.error,
  });
}

class ValidateBackupFile {
  Future<rd.Result<BackupValidationResult>> call(String filePath) async {
    try {
      LoggerService.info('Validando arquivo de backup: $filePath');

      final file = File(filePath);

      // Verificar se existe
      if (!await file.exists()) {
        return rd.Success(BackupValidationResult(
          isValid: false,
          fileSize: 0,
          lastModified: DateTime.now(),
          error: 'Arquivo não encontrado',
        ));
      }

      final stat = await file.stat();
      final fileSize = stat.size;
      final lastModified = stat.modified;

      // Verificar tamanho mínimo
      if (fileSize < 1024) {
        // Menos de 1KB
        return rd.Success(BackupValidationResult(
          isValid: false,
          fileSize: fileSize,
          lastModified: lastModified,
          error: 'Arquivo muito pequeno para ser um backup válido',
        ));
      }

      // Verificar se pode ser lido
      try {
        final randomAccess = await file.open(mode: FileMode.read);
        await randomAccess.close();
      } catch (e) {
        return rd.Success(BackupValidationResult(
          isValid: false,
          fileSize: fileSize,
          lastModified: lastModified,
          error: 'Arquivo não pode ser lido: $e',
        ));
      }

      LoggerService.info('Arquivo válido: $fileSize bytes');

      return rd.Success(BackupValidationResult(
        isValid: true,
        fileSize: fileSize,
        lastModified: lastModified,
      ));
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao validar arquivo', e, stackTrace);
      return rd.Failure(FileSystemFailure(
        message: 'Erro ao validar arquivo: $e',
        originalError: e,
      ));
    }
  }
}

