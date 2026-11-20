import 'dart:async';
import 'dart:io';

import 'package:backup_database/infrastructure/external/oauth/oauth_loopback_callback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final cancelFirst in [true, false]) {
    test(
      'should prefer cancellation over a ready response, cancelFirst=$cancelFirst',
      () async {
        final callback = OAuthLoopbackCallback(
          redirectUri: Uri.parse('http://localhost/callback'),
        );
        final response = Completer<String>();
        if (cancelFirst) callback.cancel();
        final result = callback.waitFor(response.future);
        final expectation = expectLater(result, throwsStateError);
        response.complete('stale');
        callback.cancel();
        callback.cancel();
        await expectation;
      },
    );
  }
  late HttpServer server;
  late HttpClient client;
  late Uri redirect;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = HttpClient();
    redirect = Uri.parse('http://127.0.0.1:${server.port}/callback');
  });
  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
  });
  Future<int> send(Uri uri, {String method = 'GET'}) async {
    final request = await client.openUrl(method, uri);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  }

  for (final invalid in [
    'state',
    'path',
    'method',
    'empty-code',
    'duplicate-state',
    'code-and-error',
  ]) {
    test(
      'should ignore invalid callback $invalid and accept the real response',
      () async {
        final callback = OAuthLoopbackCallback(redirectUri: redirect);
        final result = callback.receive(server, responseHtml: (_) => 'done');
        final parameters = <String, dynamic>{
          'state': callback.state,
          'code': 'valid',
        };
        if (invalid == 'state') parameters['state'] = 'unrelated';
        if (invalid == 'empty-code') parameters['code'] = '';
        if (invalid == 'duplicate-state') {
          parameters['state'] = [callback.state, callback.state];
        }
        if (invalid == 'code-and-error') parameters['error'] = 'access_denied';
        final uri = redirect.replace(
          path: invalid == 'path' ? '/favicon.ico' : redirect.path,
          queryParameters: parameters,
        );
        expect(
          await send(uri, method: invalid == 'method' ? 'POST' : 'GET'),
          HttpStatus.badRequest,
        );
        expect(
          await send(
            redirect.replace(
              queryParameters: {'state': callback.state, 'code': 'accepted'},
            ),
          ),
          HttpStatus.ok,
        );
        expect(await result, 'accepted');
      },
    );
  }
  test('should reject provider denial with matching state', () async {
    final callback = OAuthLoopbackCallback(redirectUri: redirect);
    bool? success;
    final result = callback.receive(
      server,
      responseHtml: (value) {
        success = value;
        return 'denied';
      },
    );
    final expectation = expectLater(result, throwsStateError);
    await send(
      redirect.replace(
        queryParameters: {'state': callback.state, 'error': 'access_denied'},
      ),
    );
    await expectation;
    expect(success, isFalse);
  });
  test('should time out without accepting an unrelated request', () async {
    final callback = OAuthLoopbackCallback(
      redirectUri: redirect,
      timeout: const Duration(milliseconds: 100),
    );
    final result = callback.receive(server, responseHtml: (_) => 'done');
    final expectation = expectLater(result, throwsA(isA<TimeoutException>()));
    expect(
      await send(redirect.replace(queryParameters: {'code': 'untrusted'})),
      HttpStatus.badRequest,
    );
    await expectation;
  });
  test('should generate independent state for every login', () {
    final first = OAuthLoopbackCallback(redirectUri: redirect);
    final second = OAuthLoopbackCallback(redirectUri: redirect);
    expect(first.state, isNot(second.state));
    expect(first.state.length, greaterThanOrEqualTo(43));
  });
}
