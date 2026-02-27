import 'dart:io';

import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';

class WinRarService {
  WinRarService(this._processService);
  final ProcessService _processService;
  String? _winRarPath;
  bool? _isAvailable;

  Future<bool> isAvailable() async {
    if (_isAvailable != null) {
      return _isAvailable!;
    }

    _isAvailable = false;
    _winRarPath = null;

    final possiblePaths = [
      r'C:\Program Files\WinRAR\WinRAR.exe',
      r'C:\Program Files (x86)\WinRAR\WinRAR.exe',
    ];

    for (final path in possiblePaths) {
      final file = File(path);
      final exists = await file.exists();

      if (exists) {
        _winRarPath = path;
        _isAvailable = true;
        LoggerService.info('WinRAR encontrado em: $path');
        return true;
      }
    }

    LoggerService.info('WinRAR não encontrado, usando biblioteca archive');
    return false;
  }

  String? get winRarPath => _winRarPath;

  Future<bool> compressFile({
    required String filePath,
    required String outputPath,
    CompressionFormat format = CompressionFormat.zip,
  }) async {
    if (!await isAvailable() || _winRarPath == null) {
      return false;
    }

    try {
      LoggerService.info('Comprimindo com WinRAR: $filePath → $outputPath');

      final arguments = <String>[
        'a',
        '-ep1',
        '-ibck',
        '-y',
      ];

      if (format == CompressionFormat.zip) {
        arguments.add('-afzip');
      }

      arguments.addAll([
        outputPath,
        filePath,
      ]);

      final result = await _processService.run(
        executable: _winRarPath!,
        arguments: arguments,
        timeout: StepTimeoutConstants.compression,
      );

      return result.fold(
        (processResult) {
          if (processResult.exitCode == 0) {
            LoggerService.info('Compressão WinRAR concluída com sucesso');
            return true;
          } else {
            LoggerService.warning(
              'WinRAR retornou código de saída: ${processResult.exitCode}',
            );
            LoggerService.debug('STDOUT: ${processResult.stdout}');
            LoggerService.debug('STDERR: ${processResult.stderr}');
            return false;
          }
        },
        (failure) {
          LoggerService.error('Erro ao executar WinRAR', failure);
          return false;
        },
      );
    } on Object catch (e) {
      LoggerService.error('Erro ao comprimir com WinRAR', e);
      return false;
    }
  }

  Future<bool> compressDirectory({
    required String directoryPath,
    required String outputPath,
    CompressionFormat format = CompressionFormat.zip,
  }) async {
    if (!await isAvailable() || _winRarPath == null) {
      return false;
    }

    try {
      LoggerService.info(
        'Comprimindo diretório com WinRAR: $directoryPath → $outputPath',
      );

      final arguments = <String>[
        'a',
        '-r',
        '-ep1',
        '-ibck',
        '-y',
      ];

      if (format == CompressionFormat.zip) {
        arguments.add('-afzip');
      }

      arguments.addAll([
        outputPath,
        '$directoryPath\\*',
      ]);

      final result = await _processService.run(
        executable: _winRarPath!,
        arguments: arguments,
        timeout: StepTimeoutConstants.compression,
      );

      return result.fold(
        (processResult) {
          if (processResult.exitCode == 0) {
            LoggerService.info(
              'Compressão WinRAR de diretório concluída com sucesso',
            );
            return true;
          } else {
            LoggerService.warning(
              'WinRAR retornou código de saída: ${processResult.exitCode}',
            );
            LoggerService.debug('STDOUT: ${processResult.stdout}');
            LoggerService.debug('STDERR: ${processResult.stderr}');
            return false;
          }
        },
        (failure) {
          LoggerService.error('Erro ao executar WinRAR', failure);
          return false;
        },
      );
    } on Object catch (e) {
      LoggerService.error('Erro ao comprimir diretório com WinRAR', e);
      return false;
    }
  }
}
