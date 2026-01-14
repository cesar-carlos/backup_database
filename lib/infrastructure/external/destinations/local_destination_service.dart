import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';

class LocalDestinationConfig {
  final String path;
  final bool createSubfoldersByDate;
  final int retentionDays;

  const LocalDestinationConfig({
    required this.path,
    this.createSubfoldersByDate = true,
    this.retentionDays = 30,
  });
}

class LocalUploadResult {
  final String destinationPath;
  final int fileSize;
  final Duration duration;

  const LocalUploadResult({
    required this.destinationPath,
    required this.fileSize,
    required this.duration,
  });
}

class LocalDestinationService {
  Future<rd.Result<LocalUploadResult>> upload({
    required String sourceFilePath,
    required LocalDestinationConfig config,
    String? customFileName,
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

      // Criar diretório de destino
      String destinationDir = config.path;
      if (config.createSubfoldersByDate) {
        final dateFolder = DateFormat('yyyy-MM-dd').format(DateTime.now());
        destinationDir = p.join(config.path, dateFolder);
      }

      // Verificar e criar diretório com tratamento de permissão
      final directory = Directory(destinationDir);
      try {
        if (!await directory.exists()) {
          await directory.create(recursive: true);
          LoggerService.debug('Diretório criado: $destinationDir');
        }
      } on FileSystemException catch (e) {
        stopwatch.stop();
        String errorMessage = _getPermissionErrorMessage(e, destinationDir);
        LoggerService.error('Erro ao criar diretório', e);
        return rd.Failure(
          FileSystemFailure(
            message: errorMessage,
            originalError: e,
          ),
        );
      }

      // Verificar permissão de escrita
      final canWrite = await _checkWritePermission(destinationDir);
      if (!canWrite) {
        stopwatch.stop();
        return rd.Failure(
          FileSystemFailure(
            message: 'Sem permissão de escrita no diretório: $destinationDir\n'
                'Verifique as permissões ou escolha outro diretório.',
          ),
        );
      }

      // Copiar arquivo
      final fileName = customFileName ?? p.basename(sourceFilePath);
      final destinationPath = p.join(destinationDir, fileName);
      
      try {
        final destinationFile = await sourceFile.copy(destinationPath);
        stopwatch.stop();

        final fileSize = await destinationFile.length();
        final sourceSize = await sourceFile.length();
        if (fileSize != sourceSize) {
          throw const FileSystemException(
            'Tamanho do arquivo de destino difere do arquivo de origem (cópia corrompida)',
          );
        }
        
        LoggerService.info('Arquivo copiado com sucesso: $destinationPath ($fileSize bytes)');

        return rd.Success(
          LocalUploadResult(
            destinationPath: destinationPath,
            fileSize: fileSize,
            duration: stopwatch.elapsed,
          ),
        );
      } on FileSystemException catch (e) {
        stopwatch.stop();
        String errorMessage = _getPermissionErrorMessage(e, destinationPath);
        LoggerService.error('Erro ao copiar arquivo', e);
        return rd.Failure(
          FileSystemFailure(
            message: errorMessage,
            originalError: e,
          ),
        );
      }
    } catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('Erro ao copiar para destino local', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message: 'Erro ao copiar arquivo para destino local: ${_getUserFriendlyError(e)}',
          originalError: e,
        ),
      );
    }
  }

  Future<bool> _checkWritePermission(String path) async {
    try {
      final testFile = File(p.join(path, '.write_test_${DateTime.now().millisecondsSinceEpoch}'));
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (e) {
      return false;
    }
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

      int deletedCount = 0;
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

      // Remover diretórios vazios
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
    } catch (e, stackTrace) {
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

