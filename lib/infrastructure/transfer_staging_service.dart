import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_transfer_staging_service.dart';
import 'package:path/path.dart' as p;

class TransferStagingService implements ITransferStagingService {
  TransferStagingService({required String transferBasePath})
      : _transferBasePath = p.normalize(p.absolute(transferBasePath));

  final String _transferBasePath;

  @override
  Future<String?> copyToStaging(String backupPath, String scheduleId) async {
    final source = File(backupPath);
    if (!await source.exists()) {
      LoggerService.warning(
        'TransferStagingService: backup file not found: $backupPath',
      );
      return null;
    }

    final baseName = p.basename(backupPath);
    final relativePath = p.join('remote', scheduleId, baseName);
    final destPath = p.join(_transferBasePath, relativePath);
    final destFile = File(destPath);
    final destDir = destFile.parent;

    try {
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      await source.copy(destPath);
      return p.join(relativePath).replaceAll(r'\', '/');
    } on Object catch (e, st) {
      LoggerService.warning(
        'TransferStagingService: copy failed',
        e,
        st,
      );
      return null;
    }
  }

  @override
  Future<void> cleanupStaging(String scheduleId) async {
    final scheduleDir = Directory(p.join(_transferBasePath, 'remote', scheduleId));
    if (!await scheduleDir.exists()) {
      LoggerService.debug(
        'TransferStagingService: schedule directory not found for cleanup: $scheduleId',
      );
      return;
    }

    try {
      await scheduleDir.delete(recursive: true);
      LoggerService.info(
        'TransferStagingService: cleaned up staging for schedule: $scheduleId',
      );
    } on Object catch (e, st) {
      LoggerService.warning(
        'TransferStagingService: cleanup failed for schedule: $scheduleId',
        e,
        st,
      );
    }
  }

  @override
  Future<void> cleanupOldBackups({Duration maxAge = const Duration(days: 7)}) async {
    final remoteDir = Directory(p.join(_transferBasePath, 'remote'));
    if (!await remoteDir.exists()) {
      LoggerService.debug(
        'TransferStagingService: remote directory not found for cleanup',
      );
      return;
    }

    try {
      final now = DateTime.now();
      var deletedCount = 0;
      var totalSize = 0;

      await for (final entity
          in remoteDir.list(followLinks: false, recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);
          if (age > maxAge) {
            final size = stat.size;
            await entity.delete();
            deletedCount++;
            totalSize += size;
          }
        } else if (entity is Directory) {
          // Remove diretórios vazios
          try {
            if (await entity.list().isEmpty) {
              await entity.delete();
            }
          } on Object catch (_) {
            // Ignora erro ao remover diretório vazio
          }
        }
      }

      if (deletedCount > 0) {
        LoggerService.info(
          'TransferStagingService: cleaned up $deletedCount old backup(s) '
          '(${_formatBytes(totalSize)}) older than $maxAge',
        );
      }
    } on Object catch (e, st) {
      LoggerService.warning(
        'TransferStagingService: cleanupOldBackups failed',
        e,
        st,
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
