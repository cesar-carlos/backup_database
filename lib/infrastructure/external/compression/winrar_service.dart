import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/winrar_install_probe.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';

class WinRarService {
  WinRarService(this._processService);
  final ProcessService _processService;
  String? _winRarPath;
  bool? _isAvailable;

  static Future<String?> findInstalledPath() =>
      WinrarInstallProbe.findInstalledPath();

  static Future<bool> isInstalledInSystem() =>
      WinrarInstallProbe.isInstalledInSystem();

  Future<bool> isAvailable() async {
    if (_isAvailable != null) {
      return _isAvailable!;
    }

    final detected = await findInstalledPath();
    _winRarPath = detected;
    _isAvailable = detected != null;

    if (detected != null) {
      LoggerService.info('WinRAR encontrado em: $detected');
    } else {
      LoggerService.info('WinRAR não encontrado, usando biblioteca archive');
    }

    return _isAvailable!;
  }

  String? get winRarPath => _winRarPath;

  Future<bool> compressFile({
    required String filePath,
    required String outputPath,
    CompressionFormat format = CompressionFormat.zip,
  }) {
    return _compress(
      sourceArg: filePath,
      outputPath: outputPath,
      format: format,
      recursive: false,
      kindLabel: 'arquivo',
    );
  }

  Future<bool> compressDirectory({
    required String directoryPath,
    required String outputPath,
    CompressionFormat format = CompressionFormat.zip,
  }) {
    return _compress(
      // WinRAR usa `<dir>\*` para "todo conteúdo do diretório".
      sourceArg: '$directoryPath\\*',
      outputPath: outputPath,
      format: format,
      recursive: true,
      kindLabel: 'diretório',
    );
  }

  /// Helper unificado para `compressFile` e `compressDirectory`. Antes os
  /// dois métodos tinham try/catch + invocação ao processo + parse de
  /// exitCode duplicados (~50 linhas cada). A diferença real é só:
  /// - Flag `-r` (recursive) para diretórios
  /// - Path do source (arquivo direto vs `dir\*`)
  /// - Texto da log message
  Future<bool> _compress({
    required String sourceArg,
    required String outputPath,
    required CompressionFormat format,
    required bool recursive,
    required String kindLabel,
  }) async {
    if (!await isAvailable() || _winRarPath == null) {
      return false;
    }

    try {
      LoggerService.info(
        'Comprimindo $kindLabel com WinRAR: $sourceArg → $outputPath',
      );

      final arguments = <String>[
        'a',
        if (recursive) '-r',
        '-ep1',
        '-ibck',
        '-y',
        if (format == CompressionFormat.zip) '-afzip',
        outputPath,
        sourceArg,
      ];

      final result = await _processService.run(
        executable: _winRarPath!,
        arguments: arguments,
        timeout: StepTimeoutConstants.compression,
      );

      return result.fold(
        (processResult) {
          if (processResult.exitCode == 0) {
            LoggerService.info(
              'Compressão WinRAR de $kindLabel concluída com sucesso',
            );
            return true;
          }
          LoggerService.warning(
            'WinRAR retornou código de saída: ${processResult.exitCode}',
          );
          LoggerService.debug('STDOUT: ${processResult.stdout}');
          LoggerService.debug('STDERR: ${processResult.stderr}');
          return false;
        },
        (failure) {
          LoggerService.error('Erro ao executar WinRAR', failure);
          return false;
        },
      );
    } on Object catch (e) {
      LoggerService.error('Erro ao comprimir $kindLabel com WinRAR', e);
      return false;
    }
  }
}
