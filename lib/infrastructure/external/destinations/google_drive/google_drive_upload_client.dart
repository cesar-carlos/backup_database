import 'dart:async';

import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:http/http.dart' as http;

/// A private transport for one upload attempt; abort never closes a shared client.
class GoogleDriveUploadClient extends http.BaseClient {
  GoogleDriveUploadClient(this._inner, this._token);

  final http.Client _inner;
  final String _token;
  final Stopwatch _idle = Stopwatch()..start();
  bool _closed = false;

  void touch() => _idle.reset();

  Future<T> run<T>(
    Future<T> Function() operation, {
    required Duration idleTimeout,
    bool Function()? isCancelled,
  }) async {
    final interrupted = Completer<T>();
    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final Object? error = (isCancelled?.call() ?? false)
          ? const UploadCancelledException()
          : _idle.elapsed >= idleTimeout
          ? TimeoutException('Google Drive sem progresso', idleTimeout)
          : null;
      if (error != null && !interrupted.isCompleted) {
        interrupted.completeError(error);
        close();
      }
    });
    try {
      UploadCancellation.throwIfCancelled(isCancelled);
      final value = await Future.any([operation(), interrupted.future]);
      UploadCancellation.throwIfCancelled(isCancelled);
      return value;
    } finally {
      timer.cancel();
      close();
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Google Drive transport closed');
    request.headers['Authorization'] = 'Bearer $_token';
    touch();
    final response = await _inner.send(request);
    touch();
    return http.StreamedResponse(
      response.stream.map((bytes) {
        touch();
        return bytes;
      }),
      response.statusCode,
      headers: response.headers,
      contentLength: response.contentLength,
      request: response.request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _inner.close();
  }
}
