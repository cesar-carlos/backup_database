import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/oauth/oauth_session_lock.dart';
import 'package:backup_database/infrastructure/security/machine_scope_secure_credential_service.dart';
import 'package:crypto/crypto.dart';

class UploadSessionStore {
  UploadSessionStore({
    ISecureCredentialService? credentials,
    this.directory,
    this.storageTimeout = const Duration(seconds: 30),
  }) : _credentials = credentials ?? MachineScopeSecureCredentialService();

  final ISecureCredentialService _credentials;
  final Directory? directory;
  final Duration storageTimeout;

  Future<T> run<T>(
    List<Object> identity,
    Future<T> Function(UploadSessionCheckpoint) action, {
    List<Object>? resourceIdentity,
    bool Function()? isCancelled,
  }) async {
    final guard = _CheckpointGuard(isCancelled, storageTimeout);
    final digest = sha256.convert(utf8.encode(jsonEncode(identity))).toString();
    final lockDigest = resourceIdentity == null
        ? digest
        : sha256.convert(utf8.encode(jsonEncode(resourceIdentity))).toString();
    final work =
        OAuthSessionLock(
          directory: directory,
          fileName: 'upload-$lockDigest.lock',
        ).run(
          () async {
            guard.check();
            try {
              final result = await action(
                UploadSessionCheckpoint._(
                  _credentials,
                  'upload-v1-$digest',
                  guard,
                ),
              );
              guard.check();
              return result;
            } finally {
              await guard.finish();
            }
          },
        );
    try {
      return await Future.any<T>([work, guard.stopped]);
    } finally {
      guard.dispose();
    }
  }
}

class UploadSessionCheckpoint {
  UploadSessionCheckpoint._(this._credentials, this._key, this._guard);
  final ISecureCredentialService _credentials;
  final String _key;
  final _CheckpointGuard _guard;
  bool get isStopped => _guard.isStopped;

  Future<Map<String, dynamic>?> read() async {
    if (!(await _guard.storage(() => _credentials.containsKey(key: _key)))
        .getOrThrow()) {
      return null;
    }
    final data = (await _guard.storage(() => _credentials.getToken(key: _key)))
        .getOrThrow();
    if (data['version'] != 1) {
      throw const FormatException('Versão de checkpoint inválida.');
    }
    if (data['cleared'] == true && !data.containsKey('state')) return null;
    if (data.containsKey('cleared') || data['state'] is! Map<String, dynamic>) {
      throw const FormatException('Checkpoint de envio inválido.');
    }
    return data['state'] as Map<String, dynamic>;
  }

  Future<void> save(Map<String, dynamic> state) async {
    await _write({'version': 1, 'state': state});
  }

  Future<void> clear() async {
    await _write({'version': 1, 'cleared': true});
  }

  Future<void> _write(Map<String, dynamic> value) async {
    final snapshot = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
    try {
      (await _guard.storage(
        () => _credentials.storeToken(
          key: _key,
          tokenData: snapshot,
        ),
      )).getOrThrow();
    } on Object {
      _guard.check();
      // A flushed replacement can succeed before cleanup reports a failure.
      try {
        final recovered = await _guard.storage(
          () => _credentials.getToken(key: _key),
        );
        if (recovered.isSuccess() &&
            jsonEncode(recovered.getOrNull()) == jsonEncode(snapshot)) {
          return;
        }
      } on Object {
        // Preserve the original write error when read-back is unavailable.
      }
      rethrow;
    }
  }
}

class _CheckpointGuard {
  _CheckpointGuard(this.isCancelled, this.timeout) {
    if (isCancelled != null) {
      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (isCancelled!()) interrupt(const UploadCancelledException());
      });
    }
  }
  final bool Function()? isCancelled;
  final Duration timeout;
  final _stopped = Completer<Never>();
  Timer? _timer;
  Exception? _error;
  bool _accepting = true;
  final _pending = <Future<void>>{};
  bool get isStopped => _error != null;
  Future<Never> get stopped => _stopped.future;
  void interrupt(Exception error) {
    if (_error != null) return;
    _error = error;
    _stopped.completeError(error);
  }

  void check() {
    if (_error != null) throw _error!;
    if (isCancelled?.call() ?? false) {
      interrupt(const UploadCancelledException());
      throw _error!;
    }
  }

  Future<T> storage<T>(Future<T> Function() action) {
    if (!_accepting) {
      return Future.error(StateError('Tentativa de envio já encerrada.'));
    }
    final operation = _storage(action);
    final settled = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending.add(settled);
    unawaited(
      settled.then<void>((_) {
        _pending.remove(settled);
      }),
    );
    return operation;
  }

  Future<T> _storage<T>(Future<T> Function() action) async {
    check();
    final deadline = Timer(
      timeout,
      () => interrupt(
        TimeoutException('Tempo limite ao persistir sessão de envio.', timeout),
      ),
    );
    try {
      final result = await action();
      check();
      return result;
    } finally {
      deadline.cancel();
    }
  }

  Future<void> finish() async {
    _accepting = false;
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }

  void dispose() => _timer?.cancel();
}
