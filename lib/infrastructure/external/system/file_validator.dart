import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_validation_result.dart';
import 'package:backup_database/domain/services/i_file_validator.dart';
import 'package:result_dart/result_dart.dart' as rd;

class FileValidator implements IFileValidator {
  @override
  Future<rd.Result<BackupValidationResult>> validate(String filePath) async {
    try {
      LoggerService.info('Validando arquivo de backup: $filePath');

      final file = File(filePath);

      if (!await file.exists()) {
        return rd.Success(
          BackupValidationResult(
            isValid: false,
            fileSize: 0,
            lastModified: DateTime.now(),
            error: 'Arquivo não encontrado',
          ),
        );
      }

      final stat = await file.stat();
      final fileSize = stat.size;
      final lastModified = stat.modified;

      if (fileSize < 1024) {
        return rd.Success(
          BackupValidationResult(
            isValid: false,
            fileSize: fileSize,
            lastModified: lastModified,
            error: 'Arquivo muito pequeno para ser um backup válido',
          ),
        );
      }

      try {
        final randomAccess = await file.open();
        await randomAccess.close();
      } on Object catch (e) {
        return rd.Success(
          BackupValidationResult(
            isValid: false,
            fileSize: fileSize,
            lastModified: lastModified,
            error: 'Arquivo não pode ser lido: $e',
          ),
        );
      }

      LoggerService.info('Arquivo válido: $fileSize bytes');

      return rd.Success(
        BackupValidationResult(
          isValid: true,
          fileSize: fileSize,
          lastModified: lastModified,
        ),
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao validar arquivo', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message: 'Erro ao validar arquivo: $e',
          originalError: e,
        ),
      );
    }
  }
}
