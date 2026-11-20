import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:path/path.dart' as p;

/// Serializes credential read/compare/write across UI and service processes.
/// The file remains in place: deleting a lock file permits split locks.
class OAuthSessionLock {
  OAuthSessionLock({
    this.directory,
    this.fileName = 'dropbox-session.lock',
    this.acquisitionTimeout = const Duration(seconds: 10),
    this.openFile,
  });
  final Directory? directory;
  final String fileName;
  final Duration acquisitionTimeout;
  final Future<RandomAccessFile> Function(File)? openFile;
  static final Map<String, Future<void>> _tails = {};
  static final Map<String, RandomAccessFile> _unreleased = {};

  Future<T> run<T>(Future<T> Function() action) async {
    final watch = Stopwatch()..start();
    final dir = directory ?? await resolveMachineSecretsDirectory();
    final lockPath = p.normalize(p.absolute(dir.path, fileName));
    final key = Platform.isWindows ? lockPath.toLowerCase() : lockPath;
    final previous = _tails[key] ?? Future<void>.value();
    final result = _waitAndRun(previous, action, dir, lockPath, watch);
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    // An expired waiter must not let later callers bypass the active owner.
    final tail = previous.then((_) => settled);
    _tails[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[key], tail)) {
          unawaited(_tails.remove(key));
        }
      }),
    );
    return result;
  }

  Duration _remaining(Stopwatch watch) {
    final remaining = acquisitionTimeout - watch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Armazenamento da sessão OAuth ocupado.');
    }
    return remaining;
  }

  Future<T> _waitAndRun<T>(
    Future<void> previous,
    Future<T> Function() action,
    Directory dir,
    String lockPath,
    Stopwatch watch,
  ) async {
    await previous.timeout(
      _remaining(watch),
      onTimeout: () {
        throw TimeoutException('Armazenamento da sessão OAuth ocupado.');
      },
    );
    _remaining(watch);
    return _runLocked(action, dir, lockPath, watch);
  }

  Future<T> _runLocked<T>(
    Future<T> Function() action,
    Directory dir,
    String lockPath,
    Stopwatch watch,
  ) async {
    await dir.create(recursive: true);
    final key = Platform.isWindows ? lockPath.toLowerCase() : lockPath;
    final previousHandle = _unreleased[key];
    if (previousHandle != null) {
      await _release(previousHandle, key, locked: true);
    }
    _remaining(watch);
    final file = File(lockPath);
    final handle =
        await (openFile?.call(file) ?? file.open(mode: FileMode.append));
    var locked = false;
    var operationFailed = false;
    try {
      while (!locked) {
        _remaining(watch);
        try {
          await handle.lock(FileLock.exclusive, 0, 1);
          locked = true;
        } on FileSystemException {
          final remaining = _remaining(watch);
          const pollInterval = Duration(milliseconds: 50);
          await Future<void>.delayed(
            remaining < pollInterval ? remaining : pollInterval,
          );
        }
      }
      _remaining(watch);
      return await action();
    } on Object {
      operationFailed = true;
      rethrow;
    } finally {
      try {
        await _release(handle, key, locked: locked);
      } on Object catch (error, stack) {
        if (!operationFailed) rethrow;
        LoggerService.warning(
          'Falha ao liberar bloqueio após erro da operação.',
          error,
          stack,
        );
      }
    }
  }

  Future<void> _release(
    RandomAccessFile handle,
    String key, {
    required bool locked,
  }) async {
    try {
      if (locked) await handle.unlock(0, 1);
    } on Object catch (error, stack) {
      LoggerService.warning(
        'Falha no desbloqueio; fechando o arquivo de bloqueio.',
        error,
        stack,
      );
    }
    try {
      await handle.close();
      _unreleased.remove(key);
    } on Object {
      // Do not admit another local owner while release is uncertain.
      _unreleased[key] = handle;
      rethrow;
    }
  }
}
