import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_file_transfer_lock_service.dart';
import 'package:path/path.dart' as p;

class FileTransferLockService implements IFileTransferLockService {
  FileTransferLockService({required String lockBasePath})
      : _lockBasePath = p.normalize(p.absolute(lockBasePath));

  final String _lockBasePath;

  File _getLockFile(String filePath) {
    // Usa hash do caminho como nome do arquivo de lock para evitar caracteres inválidos
    final hash = filePath.hashCode.toUnsigned(16).toRadixString(16).padLeft(8, '0');
    return File(p.join(_lockBasePath, '$hash.lock'));
  }

  @override
  Future<bool> tryAcquireLock(String filePath) async {
    final lockFile = _getLockFile(filePath);

    try {
      // Criar diretório de locks se não existir
      final lockDir = lockFile.parent;
      if (!await lockDir.exists()) {
        await lockDir.create(recursive: true);
      }

      // Verifica se já existe lock
      if (await lockFile.exists()) {
        final stat = await lockFile.stat();
        final age = DateTime.now().difference(stat.modified);
        // Lock expirado (mais de 30 minutos) pode ser sobrescrito
        if (age < const Duration(minutes: 30)) {
          LoggerService.info(
            'FileTransferLock: lock already exists for $filePath '
            '(age: ${age.inMinutes}m)',
          );
          return false;
        }
        // Lock expirado, remove e continua
        await lockFile.delete();
      }

      // Cria arquivo de lock com timestamp atual
      await lockFile.writeAsString(DateTime.now().toIso8601String());
      LoggerService.debug(
        'FileTransferLock: acquired lock for $filePath',
      );
      return true;
    } on Object catch (e, st) {
      LoggerService.warning(
        'FileTransferLock: failed to acquire lock for $filePath',
        e,
        st,
      );
      return false;
    }
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

      // Verifica se o lock não está expirado
      final stat = await lockFile.stat();
      final age = DateTime.now().difference(stat.modified);
      return age < const Duration(minutes: 30);
    } on Object catch (e, st) {
      LoggerService.warning(
        'FileTransferLock: failed to check lock for $filePath',
        e,
        st,
      );
      return false;
    }
  }

  @override
  Future<void> cleanupExpiredLocks({
    Duration maxAge = const Duration(minutes: 30),
  }) async {
    final lockDir = Directory(_lockBasePath);
    if (!await lockDir.exists()) {
      return;
    }

    try {
      final now = DateTime.now();
      var cleanedCount = 0;

      await for (final entity in lockDir.list()) {
        if (entity is File && p.extension(entity.path) == '.lock') {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);
          if (age > maxAge) {
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
