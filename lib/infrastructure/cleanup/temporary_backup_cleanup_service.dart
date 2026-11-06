import 'dart:io';

import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/services/i_temporary_backup_cleanup_service.dart';
import 'package:path/path.dart' as p;

class TemporaryBackupCleanupService implements ITemporaryBackupCleanupService {
  const TemporaryBackupCleanupService({
    required this._backupHistoryRepository,
    required this._temporaryRoots,
    required this._isBackupActive,
    this._protectedRoots,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final IBackupHistoryRepository _backupHistoryRepository;
  final DateTime Function() _clock;
  final Future<List<String>> Function() _temporaryRoots;
  final Future<List<String>> Function()? _protectedRoots;
  final bool Function() _isBackupActive;

  @override
  Future<TemporaryBackupCleanupResult> cleanupOrphanedFailedUploads({
    Duration maxAge = const Duration(hours: 24),
  }) async {
    if (maxAge <= Duration.zero) throw ArgumentError.value(maxAge, 'maxAge');
    if (_isBackupActive()) {
      return const TemporaryBackupCleanupResult(deletedCount: 0, bytesFreed: 0);
    }
    // Upload starts after the database backup has already been marked success.
    // A crash can therefore leave any status, not just an upload error.
    final historiesResult = await _backupHistoryRepository.getAll();
    if (historiesResult.isError()) {
      LoggerService.warning(
        'TemporaryBackupCleanupService: falha ao buscar historicos: '
        '${historiesResult.exceptionOrNull()}',
      );
      return const TemporaryBackupCleanupResult(
        deletedCount: 0,
        bytesFreed: 0,
      );
    }

    final cutoff = _clock().subtract(maxAge);
    final histories = historiesResult.getOrThrow();
    final recentPaths = histories
        .where(
          (history) =>
              (history.finishedAt ?? history.startedAt).isAfter(cutoff) ||
              (history.lastProgressAt?.isAfter(cutoff) ?? false),
        )
        .map((history) => history.backupPath.trim())
        .where((path) => path.isNotEmpty)
        .map((path) => p.normalize(p.absolute(path)))
        .toList();
    final roots = (await _temporaryRoots())
        .where((root) => root.trim().isNotEmpty && p.isAbsolute(root))
        .map((root) => p.normalize(p.absolute(root)))
        .toList();
    final protected = <String>[];
    for (final root in await _protectedRoots?.call() ?? <String>[]) {
      if (root.trim().isEmpty) continue;
      // Keep both spellings: a destination may be configured through a
      // junction while the temporary history uses the physical path.
      final normalized = p.normalize(p.absolute(root));
      protected.add(normalized);
      if (await FileSystemEntity.type(normalized) !=
          FileSystemEntityType.notFound) {
        protected.add(
          p.normalize(await Directory(normalized).resolveSymbolicLinks()),
        );
      }
    }
    var deletedCount = 0;
    var bytesFreed = 0;

    for (final history in histories) {
      final referenceTime = history.finishedAt ?? history.startedAt;
      if (referenceTime.isAfter(cutoff)) continue;
      if (history.lastProgressAt?.isAfter(cutoff) ?? false) continue;

      final path = history.backupPath.trim();
      if (path.isEmpty || !p.isAbsolute(path)) continue;

      final normalized = p.normalize(p.absolute(path));
      if (_isUnsafeDeletionTarget(normalized) ||
          recentPaths.any(
            (path) =>
                p.equals(path, normalized) ||
                p.isWithin(normalized, path) ||
                p.isWithin(path, normalized),
          ) ||
          !roots.any((root) => p.isWithin(root, normalized)) ||
          roots.any(
            (root) =>
                p.equals(root, normalized) || p.isWithin(normalized, root),
          ) ||
          roots.any(
            (root) => BackupType.values.any(
              (type) => p.equals(
                p.join(root, getBackupTypeDisplayName(type)),
                normalized,
              ),
            ),
          ) ||
          protected.any(
            (root) =>
                p.equals(root, normalized) ||
                p.isWithin(root, normalized) ||
                p.isWithin(normalized, root),
          )) {
        LoggerService.warning(
          'TemporaryBackupCleanupService: alvo inseguro ignorado: $normalized',
        );
        continue;
      }

      try {
        final type = await FileSystemEntity.type(
          normalized,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) {
          LoggerService.debug(
            'TemporaryBackupCleanupService: artefato ja ausente: $normalized',
          );
          continue;
        }

        // Reject junctions/symlinks at any ancestor, and preserve recently
        // touched artifacts even if a stale history references their name.
        if (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.directory) {
          continue;
        }
        final entity = type == FileSystemEntityType.file
            ? File(normalized)
            : Directory(normalized);
        if (!p.equals(await entity.resolveSymbolicLinks(), normalized)) {
          continue;
        }
        if ((await entity.stat()).modified.isAfter(cutoff)) continue;
        if (type == FileSystemEntityType.directory) {
          var unsafeOrRecent = false;
          await for (final child in Directory(
            normalized,
          ).list(recursive: true, followLinks: false)) {
            if (child is Link ||
                (await child.stat()).modified.isAfter(cutoff)) {
              unsafeOrRecent = true;
              break;
            }
          }
          if (unsafeOrRecent) continue;
        }
        final bytes = await _entityByteSize(normalized, type);
        if (_isBackupActive()) break;
        // Enumeration/size calculation can take minutes for a directory.
        // Revalidate the artifact after those awaits, immediately before removal.
        if (!await _isStillExpired(normalized, type, cutoff)) continue;
        if (_isBackupActive()) break;
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

  static bool _isUnsafeDeletionTarget(String normalizedPath) {
    final root = p.rootPrefix(normalizedPath);
    return root.isNotEmpty && p.equals(normalizedPath, root);
  }

  static Future<bool> _isStillExpired(
    String path,
    FileSystemEntityType expectedType,
    DateTime cutoff,
  ) async {
    if (await FileSystemEntity.type(path, followLinks: false) != expectedType) {
      return false;
    }
    final entity = expectedType == FileSystemEntityType.file
        ? File(path)
        : Directory(path);
    if (!p.equals(await entity.resolveSymbolicLinks(), path)) return false;
    if ((await entity.stat()).modified.isAfter(cutoff)) return false;
    if (expectedType == FileSystemEntityType.directory) {
      await for (final child in Directory(
        path,
      ).list(recursive: true, followLinks: false)) {
        if (child is Link || (await child.stat()).modified.isAfter(cutoff)) {
          return false;
        }
      }
    }
    return true;
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
