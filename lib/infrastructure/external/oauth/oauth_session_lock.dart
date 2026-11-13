import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/app_data_directory_resolver.dart';

/// Serializes credential read/compare/write across UI and service processes.
/// The file remains in place: deleting a lock file permits split locks.
class OAuthSessionLock {
  OAuthSessionLock({this.directory});
  final Directory? directory;
  static Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => _runLocked(action));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<T> _runLocked<T>(Future<T> Function() action) async {
    final dir = directory ?? await resolveMachineSecretsDirectory();
    await dir.create(recursive: true);
    final handle = await File('${dir.path}/dropbox-session.lock')
        .open(mode: FileMode.append);
    var locked = false;
    final watch = Stopwatch()..start();
    try {
      while (!locked) {
        try {
          await handle.lock(FileLock.exclusive, 0, 1);
          locked = true;
        } on FileSystemException {
          if (watch.elapsed >= const Duration(seconds: 10)) {
            throw TimeoutException('Armazenamento da sessão Dropbox ocupado.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      return await action();
    } finally {
      try {
        if (locked) await handle.unlock(0, 1);
      } finally {
        await handle.close();
      }
    }
  }
}
