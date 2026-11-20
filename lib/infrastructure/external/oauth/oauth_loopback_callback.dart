import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> launchOAuthBrowser(Uri uri) async {
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

class OAuthLoopbackCallback {
  OAuthLoopbackCallback({
    required this.redirectUri,
    this.timeout = const Duration(minutes: 5),
  }) : state = _randomValue(),
       codeVerifier = _randomValue();

  static String _randomValue() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  final Uri redirectUri;
  final Duration timeout;
  final String state;
  final String codeVerifier;
  final Completer<void> _cancelled = Completer<void>();

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  Future<T> waitFor<T>(Future<T> operation) async {
    final result = await Future.any([
      operation,
      _cancelled.future.then<T>((_) {
        throw StateError('Autenticação cancelada.');
      }),
    ]);
    if (_cancelled.isCompleted) {
      throw StateError('Autenticação cancelada.');
    }
    return result;
  }

  String get codeChallenge =>
      base64UrlEncode(sha256.convert(ascii.encode(codeVerifier)).bytes)
          .replaceAll('=', '');

  Future<String> receive(
    HttpServer server, {
    required String Function(bool) responseHtml,
  }) async {
    final result = Completer<String>();
    var accepted = false;
    Future<void> handle(HttpRequest request) async {
      final query = request.uri.queryParametersAll;
      final codes = query['code'];
      final errors = query['error'];
      final valid =
          !accepted &&
          request.method == 'GET' &&
          request.uri.path == redirectUri.path &&
          query['state']?.length == 1 &&
          query['state']!.single == state &&
          ((codes?.length == 1 && codes!.single.isNotEmpty && errors == null) ||
              (errors?.length == 1 &&
                  errors!.single.isNotEmpty &&
                  codes == null));
      if (!valid) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      accepted = true;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(responseHtml(errors == null));
      await request.response.close();
      if (result.isCompleted) return;
      if (errors != null) {
        result.completeError(
          StateError('Autenticação cancelada ou recusada pelo provedor.'),
        );
      } else {
        result.complete(codes!.single);
      }
    }

    final subscription = server.listen(
      (request) {
        unawaited(
          handle(request).catchError((Object error, StackTrace stack) {
            if (!result.isCompleted) result.completeError(error, stack);
          }),
        );
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    final timer = Timer(timeout, () {
      if (!result.isCompleted) {
        result.completeError(
          TimeoutException('Tempo limite de autenticação excedido.'),
        );
      }
    });
    try {
      return await waitFor(result.future);
    } finally {
      timer.cancel();
      accepted = true;
      await subscription.cancel();
    }
  }
}
