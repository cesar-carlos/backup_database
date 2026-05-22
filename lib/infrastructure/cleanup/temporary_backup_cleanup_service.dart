import 'dart:io';

import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/services/i_temporary_backup_cleanup_service.dart';
import 'package:path/path.dart' as p;

class TemporaryBackupCleanupService implements ITemporaryBackupCleanupService {
  const TemporaryBackupCleanupService({
    required IBackupHistoryRepository backupHistoryRepository,
    DateTime Function()? clock,
  }) : _backupHistoryRepository = backupHistoryRepository,
       _clock = clock ?? DateTime.now;

  final IBackupHistoryRepository _backupHistoryRepository;
  final DateTime Function() _clock;

  @override
  Future<TemporaryBackupCleanupResult> cleanupOrphanedFailedUploads({
    Duration maxAge = const Duration(hours: 24),
  }) async {
    final historiesResult = await _backupHistoryRepository.getByStatus(
      BackupStatus.error,
    );
    if (historiesResult.isError()) {
      LoggerService.warning(
        'TemporaryBackupCleanupService: falha ao buscar historicos com erro: '
        '${historiesResult.exceptionOrNull()}',
      );
      return const TemporaryBackupCleanupResult(
        deletedCount: 0,
        bytesFreed: 0,
      );
    }

    final cutoff = _clock().subtract(maxAge);
    var deletedCount = 0;
    var bytesFreed = 0;

    for (final history in historiesResult.getOrThrow()) {
      if (!_isFailedDestinationUpload(history)) continue;
      final referenceTime = history.finishedAt ?? history.startedAt;
      if (referenceTime.isAfter(cutoff)) continue;

      final path = history.backupPath.trim();
      if (path.isEmpty) continue;

      final normalized = p.normalize(p.absolute(path));
      if (_isUnsafeDeletionTarget(normalized)) {
        LoggerService.warning(
          'TemporaryBackupCleanupService: alvo inseguro ignorado: $normalized',
        );
        continue;
      }

      final type = await FileSystemEntity.type(normalized);
      if (type == FileSystemEntityType.notFound) {
        LoggerService.debug(
          'TemporaryBackupCleanupService: artefato ja ausente: $normalized',
        );
        continue;
      }

      try {
        final bytes = await _entityByteSize(normalized, type);
        switch (type) {
          case FileSystemEntityType.file:
            await File(normalized).delete();
          case FileSystemEntityType.directory:
            await Directory(normalized).delete(recursive: true);
          default:
            LoggerService.debug(
              'TemporaryBackupCleanupService: tipo ignorado para $normalized',
            );
            continue;
        }
        deletedCount++;
        bytesFreed += bytes;
        LoggerService.info(
          'TemporaryBackupCleanupService: removido artefato orfao '
          '${history.id}: $normalized (${ByteFormat.format(bytes)})',
        );
      } on Object catch (e, st) {
        LoggerService.warning(
          'TemporaryBackupCleanupService: falha ao remover $normalized',
          e,
          st,
        );
      }
    }

    if (deletedCount > 0) {
      LoggerService.info(
        'TemporaryBackupCleanupService: removido(s) $deletedCount '
        'artefato(s), ${ByteFormat.format(bytesFreed)} liberados',
      );
    }

    return TemporaryBackupCleanupResult(
      deletedCount: deletedCount,
      bytesFreed: bytesFreed,
    );
  }

  static bool _isFailedDestinationUpload(BackupHistory history) {
    if (history.status != BackupStatus.error) return false;
    final msg = history.errorMessage?.toLowerCase() ?? '';
    if (msg.isEmpty) return false;
    return msg.contains('upload') ||
        msg.contains('destino') ||
        msg.contains('destination') ||
        msg.contains('ftp') ||
        msg.contains('google drive') ||
        msg.contains('dropbox') ||
        msg.contains('nextcloud') ||
        msg.contains('falha ao enviar') ||
        msg.contains('failed to send');
  }

  static bool _isUnsafeDeletionTarget(String normalizedPath) {
    final root = p.rootPrefix(normalizedPath);
    return root.isNotEmpty && p.equals(normalizedPath, root);
  }

  static Future<int> _entityByteSize(
    String normalizedPath,
    FileSystemEntityType type,
  ) async {
    if (type == FileSystemEntityType.file) {
      return File(normalizedPath).length();
    }
    if (type != FileSystemEntityType.directory) {
      return 0;
    }
    var total = 0;
    await for (final entity in Directory(
      normalizedPath,
    ).list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}
