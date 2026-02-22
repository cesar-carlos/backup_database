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

      final psScript = '''
\$d = Get-PSDrive -Name $drive; "{0:N2} GB {1:N2} GB {2:N2} GB" -f (\$d.Free/1GB), ((\$d.Size-\$d.Free)/1GB), (\$d.Size/1GB)
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
      final matches = RegExp(r'(\d+(?:[.,]\d+)?)\s*(B|KB|MB|GB|TB)').allMatches(firstLine).toList();

      if (matches.length < 3) {
        return rd.Failure(
          FileSystemFailure(
            message: 'Formato de saída inesperado: "$firstLine"',
          ),
        );
      }

      final freeBytes = _parseMatch(matches[0]);
      final usedBytes = _parseMatch(matches[1]);
      final totalBytes = _parseMatch(matches[2]);

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
    final numValue = double.tryParse(match.group(1)!) ?? 0;
    final unit = match.group(2);

    if (numValue < 0 || numValue.isNaN || numValue.isInfinite) {
      LoggerService.warning('Valor numérico inválido parseado: $numValue');
      return 0;
    }

    switch (unit) {
      case 'B':
        return numValue.toInt();
      case 'KB':
        return (numValue * 1024).toInt();
      case 'MB':
        return (numValue * 1024 * 1024).toInt();
      case 'GB':
        return (numValue * 1024 * 1024 * 1024).toInt();
      case 'TB':
        return (numValue * 1024 * 1024 * 1024 * 1024).toInt();
      default:
        LoggerService.warning('Unidade desconhecida: $unit');
        return 0;
    }
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
