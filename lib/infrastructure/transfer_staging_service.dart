import 'dart:io';

import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_transfer_staging_service.dart';
import 'package:backup_database/infrastructure/socket/server/remote_staging_artifact_ttl.dart';
import 'package:path/path.dart' as p;

class TransferStagingService implements ITransferStagingService {
  TransferStagingService({
    required String transferBasePath,
    DateTime Function()? clock,
  })  : _transferBasePath = p.normalize(p.absolute(transferBasePath)),
        _clock = clock ?? DateTime.now;

  final String _transferBasePath;
  final DateTime Function() _clock;

  String _remoteKey(String scheduleId, String? remoteFolderKey) =>
      remoteFolderKey ?? scheduleId;

  @override
  Future<String?> copyToStaging(
    String backupPath,
    String scheduleId, {
    String? remoteFolderKey,
  }) async {
    final folderKey = _remoteKey(scheduleId, remoteFolderKey);
    final normalized = p.normalize(p.absolute(backupPath));
    final entityType = await FileSystemEntity.type(normalized);

    if (entityType == FileSystemEntityType.file) {
      return _copyFileToStaging(normalized, folderKey);
    }
    if (entityType == FileSystemEntityType.directory) {
      return _copyDirectoryToStaging(normalized, folderKey);
    }

    LoggerService.warning(
      'TransferStagingService: backup path not found: $backupPath',
    );
    return null;
  }

  Future<String?> _copyFileToStaging(
    String normalizedFilePath,
    String remoteKey,
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
    final relativePath = p.join('remote', remoteKey, baseName);
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
    String remoteKey,
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
    final relativePath = p.join('remote', remoteKey, baseName);
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
  Future<void> cleanupStaging(
    String scheduleId, {
    String? remoteFolderKey,
  }) async {
    final key = _remoteKey(scheduleId, remoteFolderKey);
    final targetDir = Directory(
      p.join(_transferBasePath, 'remote', key),
    );
    if (!await targetDir.exists()) {
      LoggerService.debug(
        'TransferStagingService: remote staging directory not found for cleanup: $key',
      );
      return;
    }

    try {
      await targetDir.delete(recursive: true);
      LoggerService.info(
        'TransferStagingService: cleaned up staging for remote key: $key',
      );
    } on Object catch (e, st) {
      LoggerService.warning(
        'TransferStagingService: cleanup failed for remote key: $key',
        e,
        st,
      );
    }
  }

  @override
  Future<void> cleanupOldBackups({
    Duration maxAge = const Duration(hours: 24),
  }) async {
    final remoteDir = Directory(p.join(_transferBasePath, 'remote'));
    if (!await remoteDir.exists()) {
      LoggerService.debug(
        'TransferStagingService: remote directory not found for cleanup',
      );
      return;
    }

    try {
      final ttl = RemoteStagingArtifactTtl(
        retention: maxAge,
        clock: _clock,
      );
      var removedDirs = 0;
      var totalBytes = 0;

      await for (final entity in remoteDir.list(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final child = entity;
        final newest = await RemoteStagingArtifactTtl.newestFileInTree(child);
        if (newest == null) {
          try {
            if (!await _directoryHasAnyFile(child)) {
              await child.delete();
              LoggerService.debug(
                'TransferStagingService: removed empty remote folder '
                '${p.basename(child.path)}',
              );
            }
          } on Object catch (e, st) {
            LoggerService.debug(
              'TransferStagingService: skip empty dir: $e',
              e,
              st,
            );
          }
          continue;
        }
        if (!await ttl.isFileExpiredByRetention(newest)) {
          continue;
        }
        final bytes = await _directoryByteSize(child);
        await child.delete(recursive: true);
        removedDirs++;
        totalBytes += bytes;
      }

      if (removedDirs > 0) {
        LoggerService.info(
          'TransferStagingService: removed $removedDirs remote staging folder(s) '
          '(${ByteFormat.format(totalBytes)}) past retention $maxAge',
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

  static Future<int> _directoryByteSize(Directory dir) async {
    var n = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        n += await e.length();
      }
    }
    return n;
  }

  static Future<bool> _directoryHasAnyFile(Directory dir) async {
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        return true;
      }
    }
    return false;
  }

}
