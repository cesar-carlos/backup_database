import 'dart:io';

import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_transfer_staging_service.dart';
import 'package:path/path.dart' as p;

class TransferStagingService implements ITransferStagingService {
  TransferStagingService({required String transferBasePath})
    : _transferBasePath = p.normalize(p.absolute(transferBasePath));

  final String _transferBasePath;

  @override
  Future<String?> copyToStaging(String backupPath, String scheduleId) async {
    final normalized = p.normalize(p.absolute(backupPath));
    final entityType = await FileSystemEntity.type(normalized);

    if (entityType == FileSystemEntityType.file) {
      return _copyFileToStaging(normalized, scheduleId);
    }
    if (entityType == FileSystemEntityType.directory) {
      return _copyDirectoryToStaging(normalized, scheduleId);
    }

    LoggerService.warning(
      'TransferStagingService: backup path not found: $backupPath',
    );
    return null;
  }

  Future<String?> _copyFileToStaging(
    String normalizedFilePath,
    String scheduleId,
  ) async {
    final source = File(normalizedFilePath);
    if (!await source.exists()) {
      LoggerService.warning(
        'TransferStagingService: backup file not found: '
        '$normalizedFilePath',
      );
      return null;
    }

    final baseName = p.basename(normalizedFilePath);
    final relativePath = p.join('remote', scheduleId, baseName);
    final destPath = p.join(_transferBasePath, relativePath);
    final destDir = File(destPath).parent;

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

  Future<String?> _copyDirectoryToStaging(
    String normalizedDirPath,
    String scheduleId,
  ) async {
    final sourceDir = Directory(normalizedDirPath);
    if (!await sourceDir.exists()) {
      LoggerService.warning(
        'TransferStagingService: backup directory not found: '
        '$normalizedDirPath',
      );
      return null;
    }

    final baseName = p.basename(normalizedDirPath);
    final relativePath = p.join('remote', scheduleId, baseName);
    final destRoot = Directory(p.join(_transferBasePath, relativePath));

    try {
      if (await destRoot.exists()) {
        await destRoot.delete(recursive: true);
      }
      await destRoot.create(recursive: true);
      await _copyDirectoryTree(sourceDir, destRoot);
      return p.join(relativePath).replaceAll(r'\', '/');
    } on Object catch (e, st) {
      LoggerService.warning(
        'TransferStagingService: directory copy failed',
        e,
        st,
      );
      return null;
    }
  }

  Future<void> _copyDirectoryTree(
    Directory source,
    Directory destination,
  ) async {
    await for (final FileSystemEntity entity in source.list(
      followLinks: false,
    )) {
      final name = p.basename(entity.path);
      final destPath = p.join(destination.path, name);
      if (entity is File) {
        await entity.copy(destPath);
      } else if (entity is Directory) {
        await Directory(destPath).create(recursive: true);
        await _copyDirectoryTree(Directory(entity.path), Directory(destPath));
      }
    }
  }

  @override
  Future<void> cleanupStaging(String scheduleId) async {
    final scheduleDir = Directory(
      p.join(_transferBasePath, 'remote', scheduleId),
    );
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
  Future<void> cleanupOldBackups({
    Duration maxAge = const Duration(days: 7),
  }) async {
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

      await for (final entity in remoteDir.list(
        followLinks: false,
        recursive: true,
      )) {
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
          } on Object catch (e, st) {
            LoggerService.debug(
              'TransferStagingService: skip empty dir removal: $e',
              e,
              st,
            );
          }
        }
      }

      if (deletedCount > 0) {
        LoggerService.info(
          'TransferStagingService: cleaned up $deletedCount old backup(s) '
          '(${ByteFormat.format(totalSize)}) older than $maxAge',
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

}
