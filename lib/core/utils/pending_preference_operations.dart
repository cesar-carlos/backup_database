import 'dart:async';

/// An in-flight change may finish during shutdown, but must not start another
/// storage/native operation after shutdown's bounded drain has expired.
class PreferenceOperation {
  bool _valid = true;
  final _done = Completer<void>();
  bool get isValid => _valid;
}

class PendingPreferenceOperations {
  PendingPreferenceOperations._();
  static final _active = <PreferenceOperation>{};

  static Future<void> run(
    Future<void> Function(PreferenceOperation) action,
  ) async {
    final operation = PreferenceOperation();
    _active.add(operation);
    try {
      await action(operation);
    } finally {
      _active.remove(operation);
      operation._done.complete();
    }
  }

  static Future<bool> drain({required Duration timeout}) async {
    final pending = _active.toList();
    try {
      await Future.wait(pending.map((operation) => operation._done.future))
          .timeout(timeout);
      return true;
    } on TimeoutException {
      for (final operation in pending) {
        operation._valid = false;
      }
      return false;
    }
  }
}
