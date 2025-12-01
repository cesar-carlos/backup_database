import 'dart:io';

import '../../../core/utils/logger_service.dart';
import '../process/process_service.dart';

class WinRarService {
  final ProcessService _processService;
  String? _winRarPath;
  bool? _isAvailable;

  WinRarService(this._processService);

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
      if (await file.exists()) {
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
  }) async {
    if (!await isAvailable() || _winRarPath == null) {
      return false;
    }

    try {
      LoggerService.info('Comprimindo com WinRAR: $filePath → $outputPath');

      final arguments = [
        'a', // Adicionar ao arquivo
        '-afzip', // Formato ZIP (não RAR)
        '-ep1', // Excluir caminho base do arquivo
        '-ibck', // Executar em background (sem mostrar janela)
        '-y', // Sim para todas as perguntas
        outputPath, // Arquivo de saída
        filePath, // Arquivo a comprimir
      ];

      final result = await _processService.run(
        executable: _winRarPath!,
        arguments: arguments,
        timeout: const Duration(hours: 1),
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
    } catch (e) {
      LoggerService.error('Erro ao comprimir com WinRAR', e);
      return false;
    }
  }

  Future<bool> compressDirectory({
    required String directoryPath,
    required String outputPath,
  }) async {
    if (!await isAvailable() || _winRarPath == null) {
      return false;
    }

    try {
      LoggerService.info('Comprimindo diretório com WinRAR: $directoryPath → $outputPath');

      final arguments = [
        'a', // Adicionar ao arquivo
        '-afzip', // Formato ZIP (não RAR)
        '-r', // Recursivo (incluir subdiretórios)
        '-ep1', // Excluir caminho base
        '-ibck', // Executar em background (sem mostrar janela)
        '-y', // Sim para todas as perguntas
        outputPath, // Arquivo de saída
        '$directoryPath\\*', // Todos os arquivos do diretório
      ];

      final result = await _processService.run(
        executable: _winRarPath!,
        arguments: arguments,
        timeout: const Duration(hours: 2),
      );

      return result.fold(
        (processResult) {
          if (processResult.exitCode == 0) {
            LoggerService.info('Compressão WinRAR de diretório concluída com sucesso');
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
    } catch (e) {
      LoggerService.error('Erro ao comprimir diretório com WinRAR', e);
      return false;
    }
  }
}
