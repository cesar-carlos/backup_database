import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class DiskSpaceInfo {
  const DiskSpaceInfo({
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
    required this.usedPercentage,
  });
  final int totalBytes;
  final int freeBytes;
  final int usedBytes;
  final double usedPercentage;

  bool hasEnoughSpace(int requiredBytes) => freeBytes >= requiredBytes;
}

class CheckDiskSpace {
  Future<rd.Result<DiskSpaceInfo>> call(String path) async {
    try {
      // No Windows, usar WMIC para obter informações do disco
      final drive = path.substring(0, 2); // Ex: "C:"

      final result = await Process.run(
        'wmic',
        ['logicaldisk', 'where', 'DeviceID="$drive"', 'get', 'Size,FreeSpace'],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        return rd.Failure(
          FileSystemFailure(
            message: 'Erro ao verificar espaço em disco: ${result.stderr}',
          ),
        );
      }

      final output = result.stdout.toString().trim();
      final lines = output
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();

      if (lines.length < 2) {
        return const rd.Failure(
          FileSystemFailure(
            message: 'Não foi possível obter informações do disco',
          ),
        );
      }

      final values = lines[1].trim().split(RegExp(r'\s+'));
      if (values.length < 2) {
        return const rd.Failure(
          FileSystemFailure(
            message: 'Formato de saída inesperado',
          ),
        );
      }

      final freeBytes = int.tryParse(values[0]) ?? 0;
      final totalBytes = int.tryParse(values[1]) ?? 0;
      final usedBytes = totalBytes - freeBytes;
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
