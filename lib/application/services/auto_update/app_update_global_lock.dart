import 'dart:io';

import 'package:backup_database/application/services/auto_update/app_update_types.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:path/path.dart' as p;

class AppUpdateGlobalLock {
  AppUpdateGlobalLock({
    required this.locksDirectoryResolver,
    required this.processAliveCheck,
  });

  final DirectoryResolver locksDirectoryResolver;
  final ProcessAliveCheck processAliveCheck;

  Future<AppUpdateLockHandle?> tryAcquire({
    required AppUpdateSource source,
    required String currentVersion,
    required int attemptNumber,
  }) async {
    final locksDir = await locksDirectoryResolver();
    final handle = await tryAcquireGlobalLock(
      locksDir: locksDir,
      metadata: {
        'source': source.name,
        'currentVersion': currentVersion,
        'attempt': '$attemptNumber',
        'stage': AppUpdateStage.fetchingFeed.token,
      },
      processAliveCheck: processAliveCheck,
    );
    if (handle == null) {
      LoggerService.info(
        'AutoUpdateService: lock global ocupado por outro processo',
      );
    }
    return handle;
  }

  static Future<AppUpdateLockHandle?> tryAcquireGlobalLock({
    required Directory locksDir,
    required Map<String, String?> metadata,
    Duration staleAfter = AppUpdateConstants.defaultLockStaleAfter,
    DateTime? now,
    ProcessAliveCheck? processAliveCheck,
  }) async {
    await locksDir.create(recursive: true);

    final lockFile = File(
      p.join(locksDir.path, AppUpdateConstants.lockFileName),
    );
    final acquiredAt = (now ?? DateTime.now()).toUtc();
    final aliveCheck = processAliveCheck ?? defaultProcessAliveCheck;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await lockFile.create(exclusive: true);
        final handle = AppUpdateLockHandle(lockFile);
        await handle.updateMetadata({
          'pid': '$pid',
          'acquiredAt': acquiredAt.toIso8601String(),
          ...metadata,
        });
        return handle;
      } on PathExistsException {
        final ownerPid = await _readLockOwnerPid(lockFile);
        final ownerAlive = ownerPid == null || aliveCheck(ownerPid);
        final isStaleByAge = await _isStaleLockFile(
          lockFile,
          staleAfter: staleAfter,
          now: acquiredAt,
        );

        // Considera obsoleto se (a) excedeu janela de stale OU (b) o
        // processo dono nao existe mais no S.O. Combinacao reduz a janela
        // de bloqueio apos crash do dono (antes esperavamos 2h cheias).
        final isStale = isStaleByAge || !ownerAlive;
        if (!isStale) {
          final summary = await _describeLockOwner(lockFile);
          LoggerService.info(
            'AutoUpdateService: lock global ainda valido em '
            '${lockFile.path}${summary == null ? '' : ' ($summary)'}',
          );
          return null;
        }
        if (!ownerAlive) {
          LoggerService.warning(
            'AutoUpdateService: lock global pertence ao pid=$ownerPid '
            'que nao existe mais; tratando como stale.',
          );
        }

        try {
          await lockFile.delete();
        } on Object catch (e, s) {
          LoggerService.info(
            'AutoUpdateService: lock obsoleto nao pode ser removido',
            e,
            s,
          );
          return null;
        }
      } on FileSystemException catch (e, s) {
        LoggerService.info(
          'AutoUpdateService: falha ao adquirir lock global',
          e,
          s,
        );
        return null;
      }
    }

    return null;
  }

  /// Heuristica leve para checar se um PID Windows segue ativo. Usa
  /// `tasklist /FI` com filtro por PID. Em qualquer falha, retorna `true`
  /// (assume vivo) para nao remover um lock potencialmente valido por engano.
  static bool defaultProcessAliveCheck(int pid) {
    if (!Platform.isWindows || pid <= 0) {
      return true;
    }
    try {
      final result = Process.runSync('tasklist.exe', <String>[
        '/FI',
        'PID eq $pid',
        '/NH',
      ]);
      if (result.exitCode != 0) {
        return true;
      }
      final output = result.stdout.toString();
      // `tasklist` imprime "INFO: No tasks are running..." quando nao encontra.
      return !output.contains('No tasks are running') &&
          !output.contains('Nenhuma tarefa em execu');
    } on Object {
      return true;
    }
  }

  static Future<int?> _readLockOwnerPid(File file) async {
    try {
      final lines = await file.readAsLines();
      for (final line in lines) {
        final separator = line.indexOf('=');
        if (separator <= 0) {
          continue;
        }
        final key = line.substring(0, separator).trim();
        if (key != 'pid') {
          continue;
        }
        final value = line.substring(separator + 1).trim();
        return int.tryParse(value);
      }
    } on Object {
      // Ignorado: arquivo pode estar parcialmente escrito.
    }
    return null;
  }

  static Future<String?> _describeLockOwner(File file) async {
    try {
      final lines = await file.readAsLines();
      if (lines.isEmpty) {
        return null;
      }

      final parts = <String>[];
      for (final line in lines) {
        final separatorIndex = line.indexOf('=');
        if (separatorIndex <= 0) {
          continue;
        }
        final key = line.substring(0, separatorIndex).trim();
        final value = line.substring(separatorIndex + 1).trim();
        if (key.isEmpty || value.isEmpty) {
          continue;
        }
        if (key == 'source' ||
            key == 'attempt' ||
            key == 'stage' ||
            key == 'targetVersion') {
          parts.add('$key=$value');
        }
      }
      if (parts.isEmpty) {
        return null;
      }
      return parts.join(', ');
    } on Object {
      return null;
    }
  }

  static Future<bool> _isStaleLockFile(
    File file, {
    required Duration staleAfter,
    required DateTime now,
  }) async {
    try {
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return false;
      }
      return now.difference(stat.modified.toUtc()) > staleAfter;
    } on Object {
      return false;
    }
  }
}
