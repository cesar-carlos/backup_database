import 'dart:async';

/// Locks por path de destino para evitar que `cleanOldBackups` apague
/// arquivos `.tmp` em uso por um upload concorrente, ou que dois
/// uploads para o mesmo destino se atropelem.
///
/// Usamos um `Completer<void>` por path: enquanto o lock está mantido,
/// outras chamadas aguardam o `future`.
class LocalDestinationPathLock {
  static final Map<String, Future<void>> _destinationLocks = {};

  Future<T> withLock<T>(
    String destinationPath,
    Future<T> Function() operation,
  ) async {
    while (_destinationLocks.containsKey(destinationPath)) {
      try {
        await _destinationLocks[destinationPath];
      } on Object catch (_) {
        // Erro do owner anterior — não é problema do próximo na fila.
      }
    }
    final completer = Completer<void>();
    _destinationLocks[destinationPath] = completer.future;
    try {
      return await operation();
    } finally {
      unawaited(
        _destinationLocks.remove(destinationPath) ?? Future<void>.value(),
      );
      if (!completer.isCompleted) completer.complete();
    }
  }
}
