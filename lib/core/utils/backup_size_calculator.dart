import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class BackupSizeCalculator {
  BackupSizeCalculator._();

  static Future<rd.Result<int>> bytesOfFile(String path) async {
    try {
      final backupFile = File(path);
      if (!await backupFile.exists()) {
        return rd.Failure(
          BackupFailure(
            message: 'Arquivo de backup não existe: $path',
            originalError: Exception('Arquivo não encontrado'),
          ),
        );
      }

      final fileSize = await backupFile.length();
      return rd.Success(fileSize);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao calcular tamanho do arquivo', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao calcular tamanho do arquivo: $e',
          originalError: e,
        ),
      );
    }
  }

  static Future<rd.Result<int>> bytesOfDirectoryTree(String path) async {
    try {
      final backupDir = Directory(path);
      if (!await backupDir.exists()) {
        return rd.Failure(
          BackupFailure(
            message: 'Diretório de backup não existe: $path',
            originalError: Exception('Diretório não encontrado'),
          ),
        );
      }

      var totalSize = 0;
      await for (final FileSystemEntity entity in backupDir.list(
        recursive: true,
      )) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      return rd.Success(totalSize);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao calcular tamanho do backup', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao calcular tamanho do backup: $e',
          originalError: e,
        ),
      );
    }
  }

  static Future<int> sumBytesInDirectoryShallow(Directory directory) async {
    if (!await directory.exists()) {
      return 0;
    }
    var sum = 0;
    await for (final FileSystemEntity entity in directory.list()) {
      if (entity is File) {
        sum += await entity.length();
      }
    }
    return sum;
  }

  static Future<rd.Result<int>> bytesOfExistingFiles(
    List<String> paths,
  ) async {
    try {
      var sum = 0;
      for (final path in paths) {
        final file = File(path);
        if (!await file.exists()) {
          return rd.Failure(
            BackupFailure(
              message: 'Arquivo de backup não existe: $path',
              originalError: Exception('Arquivo não encontrado'),
            ),
          );
        }
        sum += await file.length();
      }
      return rd.Success(sum);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao somar tamanho dos arquivos de backup',
        e,
        stackTrace,
      );
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao somar tamanho dos arquivos de backup: $e',
          originalError: e,
        ),
      );
    }
  }
}
