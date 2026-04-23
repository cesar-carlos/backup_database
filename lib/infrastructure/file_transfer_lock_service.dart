import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/constants/transfer_lease.dart';
import 'package:backup_database/domain/services/i_file_transfer_lock_service.dart';
import 'package:backup_database/infrastructure/file_transfer_lease.dart';
import 'package:path/path.dart' as p;

class FileTransferLockService implements IFileTransferLockService {
  FileTransferLockService({
    required String lockBasePath,
    DateTime Function()? clock,
  }) : _lockBasePath = p.normalize(p.absolute(lockBasePath)),
       _clock = clock ?? DateTime.now;

  final String _lockBasePath;
  final DateTime Function() _clock;

  File _getLockFile(String filePath) {
    final key = p.normalize(p.absolute(filePath));
    final hash = key.hashCode
        .toUnsigned(16)
        .toRadixString(16)
        .padLeft(8, '0');
    return File(p.join(_lockBasePath, '$hash.lock'));
  }

  Future<void> _ensureLockDirExists(File lockFile) async {
    final lockDir = lockFile.parent;
    if (!await lockDir.exists()) {
      await lockDir.create(recursive: true);
    }
  }

  @override
  Future<bool> tryAcquireLock(
    String filePath, {
    String owner = 'unknown',
    String? runId,
    Duration leaseTtl = kDefaultTransferLeaseTtl,
  }) async {
    final lockFile = _getLockFile(filePath);
    final now = _clock();
    final normPath = normalizedFilePathKey(filePath);

    try {
      await _ensureLockDirExists(lockFile);

      if (await lockFile.exists()) {
        final text = (await lockFile.readAsString()).trim();
        final v1 = FileTransferLeaseV1.tryParse(text);
        if (v1 != null) {
          if (now.isBefore(v1.expiresAt)) {
            if (fileTransferSameLeaseHolder(
              existing: v1,
              owner: owner,
              runId: runId,
            )) {
              return _writeV1(
                lockFile: lockFile,
                filePath: normPath,
                owner: owner,
                runId: runId,
                now: now,
                leaseTtl: leaseTtl,
              );
            }
            LoggerService.info(
              'FileTransferLock: lease ativo (outro ator) para $normPath',
            );
            return false;
          }
          await lockFile.delete();
        } else {
          final legacy = FileTransferLeaseV1.tryParseLegacyContent(text);
          if (legacy != null) {
            final exp = legacy.add(leaseTtl);
            if (now.isBefore(exp)) {
              // Legado: sem owner/runId — nao permitimos "tomar" de outro
              // ator; bloquear ate expirar.
              LoggerService.info(
                'FileTransferLock: lock legado ainda valido para $normPath',
              );
              return false;
            }
            await lockFile.delete();
          } else {
            // Corrompido ou desconhecido — remove e segue
            await lockFile.delete();
          }
        }
      }

      return _writeV1(
        lockFile: lockFile,
        filePath: normPath,
        owner: owner,
        runId: runId,
        now: now,
        leaseTtl: leaseTtl,
      );
    } on Object catch (e, st) {
      LoggerService.warning(
        'FileTransferLock: failed to acquire lock for $normPath',
        e,
        st,
      );
      return false;
    }
  }

  Future<bool> _writeV1({
    required File lockFile,
    required String filePath,
    required String owner,
    required String? runId,
    required DateTime now,
    required Duration leaseTtl,
  }) async {
    final acquiredAt = now;
    final expiresAt = now.add(leaseTtl);
    final payload = FileTransferLeaseV1(
      filePath: filePath,
      owner: owner,
      acquiredAt: acquiredAt,
      expiresAt: expiresAt,
      runId: runId,
    );
    await lockFile.writeAsString(
      jsonEncode(payload.toJson()),
    );
    LoggerService.debug(
      'FileTransferLock: acquired lease for $filePath owner=$owner '
      'runId=$runId until ${expiresAt.toIso8601String()}',
    );
    return true;
  }

  @override
  Future<void> releaseLock(String filePath) async {
    final lockFile = _getLockFile(filePath);

    try {
      if (await lockFile.exists()) {
        await lockFile.delete();
        LoggerService.debug(
          'FileTransferLock: released lock for $filePath',
        );
      }
    } on Object catch (e, st) {
      LoggerService.warning(
        'FileTransferLock: failed to release lock for $filePath',
        e,
        st,
      );
    }
  }

  @override
  Future<bool> isLocked(String filePath) async {
    final lockFile = _getLockFile(filePath);

    try {
      if (!await lockFile.exists()) {
        return false;
      }
      return !(await _isLockExpired(lockFile));
    } on Object catch (e, st) {
      LoggerService.warning(
        'FileTransferLock: failed to check lock for $filePath',
        e,
        st,
      );
      return false;
    }
  }

  Future<bool> _isLockExpired(
    File lockFile, {
    Duration leaseTtl = kDefaultTransferLeaseTtl,
  }) async {
    final now = _clock();
    final text = (await lockFile.readAsString()).trim();
    final v1 = FileTransferLeaseV1.tryParse(text);
    if (v1 != null) {
      return v1.expiresAt.isBefore(now);
    }
    final legacy = FileTransferLeaseV1.tryParseLegacyContent(text);
    if (legacy != null) {
      return !now.isBefore(legacy.add(leaseTtl));
    }
    // Corrompido: tratar como expirado
    return true;
  }

  @override
  Future<void> cleanupExpiredLocks({
    Duration maxAge = kDefaultTransferLeaseTtl,
  }) async {
    final lockDir = Directory(_lockBasePath);
    if (!await lockDir.exists()) {
      return;
    }

    try {
      final now = _clock();
      var cleanedCount = 0;

      await for (final entity in lockDir.list()) {
        if (entity is File && p.extension(entity.path) == '.lock') {
          final text = (await entity.readAsString()).trim();
          var drop = false;
          final v1 = FileTransferLeaseV1.tryParse(text);
          if (v1 != null) {
            drop = v1.expiresAt.isBefore(now);
          } else {
            final legacy = FileTransferLeaseV1.tryParseLegacyContent(text);
            if (legacy != null) {
              drop = !now.isBefore(legacy.add(maxAge));
            } else {
              // Desconhecido: usa mtime como fallback
              final stat = await entity.stat();
              drop = now.difference(stat.modified) > maxAge;
            }
          }
          if (drop) {
            await entity.delete();
            cleanedCount++;
          }
        }
      }

      if (cleanedCount > 0) {
        LoggerService.info(
          'FileTransferLock: cleaned up $cleanedCount expired lock(s)',
        );
      }
    } on Object catch (e, st) {
      LoggerService.warning(
        'FileTransferLock: cleanupExpiredLocks failed',
        e,
        st,
      );
    }
  }
}
