import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/disk_space_info.dart';
import 'package:backup_database/domain/services/i_storage_checker.dart';
import 'package:result_dart/result_dart.dart' as rd;

class StorageChecker implements IStorageChecker {
  static const _minPathLength = 2;

  @override
  Future<rd.Result<DiskSpaceInfo>> checkSpace(String path) async {
    try {
      if (path.length < _minPathLength) {
        return const rd.Failure(
          FileSystemFailure(
            message: 'Caminho inválido para verificar espaço em disco',
          ),
        );
      }

      final drive = path[0];
      final validDrive = RegExp(r'^[A-Za-z]$').hasMatch(drive);

      if (!validDrive) {
        return rd.Failure(
          FileSystemFailure(
            message: 'Formato de unidade inválido: $drive',
          ),
        );
      }

      final psScript =
          '''
\$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive:'"; \$freeGB = [math]::Round(\$disk.FreeSpace/1GB, 2); \$usedGB = [math]::Round((\$disk.Size-\$disk.FreeSpace)/1GB, 2); \$totalGB = [math]::Round(\$disk.Size/1GB, 2); "{0:N2} GB {1:N2} GB {2:N2} GB" -f \$freeGB, \$usedGB, \$totalGB
''';

      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', psScript],
      );

      if (result.exitCode != 0) {
        return rd.Failure(
          FileSystemFailure(
            message: 'Erro ao verificar espaço em disco: ${result.stderr}',
          ),
        );
      }

      final output = result.stdout.toString().trim();
      LoggerService.debug('PowerShell output: "$output"');

      final lines = output
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        return const rd.Failure(
          FileSystemFailure(
            message: 'Não foi possível obter informações do disco',
          ),
        );
      }

      final firstLine = lines[0].trim();
      LoggerService.debug('First line from output: "$firstLine"');

      final matches = RegExp(
        r'(\d+(?:[.,]\d+)?)\s*(B|KB|MB|GB|TB)',
      ).allMatches(firstLine).toList();
      LoggerService.debug('Regex matches found: ${matches.length}');

      if (matches.length != 3) {
        return rd.Failure(
          FileSystemFailure(
            message: 'Formato de saída inesperado: "$firstLine"',
          ),
        );
      }

      LoggerService.debug(
        'Match 0: ${matches[0].group(0)} -> number: ${matches[0].group(1)}, unit: ${matches[0].group(2)}',
      );
      LoggerService.debug(
        'Match 1: ${matches[1].group(0)} -> number: ${matches[1].group(1)}, unit: ${matches[1].group(2)}',
      );
      LoggerService.debug(
        'Match 2: ${matches[2].group(0)} -> number: ${matches[2].group(1)}, unit: ${matches[2].group(2)}',
      );

      final freeBytes = _parseMatch(matches[0]);
      final usedBytes = _parseMatch(matches[1]);
      final totalBytes = _parseMatch(matches[2]);

      LoggerService.debug(
        'Parsed bytes - Free: $freeBytes, Used: $usedBytes, Total: $totalBytes',
      );

      if (freeBytes <= 0 || usedBytes < 0 || totalBytes <= 0) {
        return const rd.Failure(
          FileSystemFailure(
            message: 'Valores de espaço em disco inválidos detectados',
          ),
        );
      }

      final calculatedUsed = totalBytes - freeBytes;
      final tolerance = totalBytes * 0.01;
      if ((calculatedUsed - usedBytes).abs() > tolerance) {
        LoggerService.warning(
          'Inconsistência nos valores: total=$totalBytes, free=$freeBytes, used=$usedBytes, calculated=$calculatedUsed',
        );
      }

      final usedPercentage = totalBytes > 0
          ? (usedBytes / totalBytes) * 100
          : 0.0;

      LoggerService.info(
        'Espaço em disco $drive: ${_formatBytes(freeBytes)} livres de '
        '${_formatBytes(totalBytes)}',
      );

      return rd.Success(
        DiskSpaceInfo(
          totalBytes: totalBytes,
          freeBytes: freeBytes,
          usedBytes: usedBytes,
          usedPercentage: usedPercentage,
        ),
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao verificar espaço em disco', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message: 'Erro ao verificar espaço em disco: $e',
          originalError: e,
        ),
      );
    }
  }

  int _parseMatch(RegExpMatch match) {
    final fullMatch = match.group(0);
    final numStr = match.group(1);
    final unit = match.group(2);

    LoggerService.debug(
      'Parsing match - full: $fullMatch, numStr: $numStr, unit: $unit',
    );

    final normalizedNumStr = (numStr ?? '').replaceAll(',', '.');
    final numValue = double.tryParse(normalizedNumStr);

    if (numValue == null) {
      LoggerService.warning('Falha ao parsear número: "$numStr"');
      return 0;
    }

    if (numValue < 0 || numValue.isNaN || numValue.isInfinite) {
      LoggerService.warning('Valor numérico inválido parseado: $numValue');
      return 0;
    }

    final bytes = switch (unit) {
      'B' => numValue.toInt(),
      'KB' => (numValue * 1024).toInt(),
      'MB' => (numValue * 1024 * 1024).toInt(),
      'GB' => (numValue * 1024 * 1024 * 1024).toInt(),
      'TB' => (numValue * 1024 * 1024 * 1024 * 1024).toInt(),
      _ => () {
        LoggerService.warning('Unidade desconhecida: $unit');
        return 0;
      }(),
    };

    LoggerService.debug('Converted $numValue $unit to $bytes bytes');
    return bytes;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
