import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_service.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' hide unit;

class _Credentials extends Mock implements ISecureCredentialService {}

void main() {
  for (final provider in ['Google', 'Dropbox']) {
    for (final scenario in [
      'success',
      'retry-cancel',
      'retry-cancel-again',
      'retry-cancel-failed',
      'retry-late-token',
      'retry-network',
      'retry-account-network',
      'retry-account-timeout',
      'logout',
      'launch-failed',
      'cancel-wait',
      'exchange-failed',
      'exchange-empty',
      'exchange-timeout',
      'exchange-logout',
    ]) {
      test(
        'should protect $provider browser exchange during $scenario',
        () async {
          final store = _Credentials();
          final deletionEntered = Completer<void>();
          final releaseDeletion = Completer<void>();
          final firstLaunch = Completer<void>();
          var launches = 0;
          Uri? oldAuthorization;
          when(
            () => store.containsKey(key: any(named: 'key')),
          ).thenAnswer((_) async => Success(scenario == 'retry-cancel-failed'));
          when(() => store.getToken(key: any(named: 'key')))
              .thenAnswer((_) async => const Success(<String, dynamic>{}));
          when(() => store.deleteToken(key: any(named: 'key')))
              .thenAnswer((_) async {
                if (scenario.startsWith('retry-cancel')) {
                  deletionEntered.complete();
                  await releaseDeletion.future;
                  if (scenario == 'retry-cancel-failed') {
                    return Failure(Exception('storage unavailable'));
                  }
                }
                return const Success(unit);
              });
          when(
            () => store.storeToken(
              key: any(named: 'key'),
              tokenData: any(named: 'tokenData'),
            ),
          ).thenAnswer((_) async => const Success(unit));
          final browser = HttpClient();
          addTearDown(() => browser.close(force: true));
          late Future<void> Function() logout;
          late Uri authorization;
          Future<void>? browserRequest;
          var exchanges = 0;
          var accountRequests = 0;
          final releaseExchange = Completer<void>();
          final tokenStarted = Completer<void>();
          Future<void>? cancellation;
          Future<bool> launch(Uri uri) async {
            authorization = uri;
            launches++;
            if (scenario.startsWith('retry-cancel') && launches == 1) {
              oldAuthorization = uri;
              firstLaunch.complete();
              return true;
            }
            if (scenario == 'launch-failed') return false;
            if (scenario == 'logout') {
              await logout();
              return true;
            }
            if (scenario == 'cancel-wait') {
              cancellation = Future<void>.delayed(
                const Duration(milliseconds: 20),
                logout,
              );
              return true;
            }
            browserRequest = (() async {
              final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
              if (oldAuthorization != null) {
                final stale = await browser.getUrl(
                  redirect.replace(
                    queryParameters: {
                      'code': 'old-code',
                      'state': oldAuthorization!.queryParameters['state'],
                    },
                  ),
                );
                stale.persistentConnection = false;
                final staleResponse = await stale.close();
                await staleResponse.drain<void>();
                expect(staleResponse.statusCode, HttpStatus.badRequest);
              }
              final request = await browser.getUrl(
                redirect.replace(
                  queryParameters: {
                    'code': 'browser-code',
                    'state': uri.queryParameters['state'],
                  },
                ),
              );
              request.persistentConnection = false;
              final response = await request.close();
              await response.drain<void>();
            })();
            return true;
          }

          void verifyExchange(Map<String, dynamic> body) {
            exchanges++;
            final verifier = body['code_verifier'] as String;
            expect(verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43,128}$')));
            expect(body['code'], 'browser-code');
            expect(
              authorization.queryParameters['code_challenge_method'],
              'S256',
            );
            expect(
              authorization.queryParameters['code_challenge'],
              base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
                  .replaceAll('=', ''),
            );
            expect(
              authorization.queryParameters.containsKey('code_verifier'),
              isFalse,
            );
            expect(verifier, isNot(authorization.queryParameters['state']));
          }

          final tokens = {
            'access_token': scenario == 'exchange-empty' ? '' : 'access',
            'refresh_token': 'refresh',
            'expires_in': 3600,
            'token_type': 'Bearer',
          };
          late Future<bool> Function() login;
          if (provider == 'Google') {
            final client = MockClient((request) async {
              if (request.url.path.endsWith('/token')) {
                verifyExchange(request.bodyFields);
                if (scenario == 'retry-late-token' && exchanges == 1) {
                  tokenStarted.complete();
                  await releaseExchange.future;
                }
                if (scenario == 'retry-network' && exchanges == 1) {
                  throw const SocketException('connection interrupted');
                }
                if (scenario == 'exchange-timeout') {
                  await releaseExchange.future;
                }
                if (scenario == 'exchange-logout') await logout();
                if (scenario == 'exchange-failed') {
                  return http.Response('{}', 400);
                }
                return http.Response(jsonEncode(tokens), 200);
              }
              accountRequests++;
              if (accountRequests == 1 && scenario == 'retry-account-network') {
                throw const SocketException('account connection interrupted');
              }
              if (accountRequests == 1 && scenario == 'retry-account-timeout') {
                await releaseExchange.future;
              }
              return http.Response('{"email":"user@example.test"}', 200);
            });
            addTearDown(client.close);
            final auth = GoogleAuthService(
              store,
              httpClient: client,
              launchBrowser: launch,
              requestTimeout: scenario.contains('timeout')
                  ? const Duration(milliseconds: 50)
                  : const Duration(seconds: 30),
            );
            await auth.initialize(clientId: 'client');
            logout = auth.signOut;
            login = () async => (await auth.signIn()).isSuccess();
          } else {
            final dio = Dio();
            addTearDown(() => dio.close(force: true));
            dio.interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) async {
                  final tokenRequest = options.path == '/oauth2/token';
                  if (tokenRequest) {
                    verifyExchange(options.data as Map<String, dynamic>);
                    if (scenario == 'retry-late-token' && exchanges == 1) {
                      tokenStarted.complete();
                      await releaseExchange.future;
                    }
                    if (scenario == 'retry-network' && exchanges == 1) {
                      handler.reject(
                        DioException(
                          requestOptions: options,
                          type: DioExceptionType.connectionError,
                        ),
                      );
                      return;
                    }
                    if (scenario == 'exchange-timeout') {
                      await releaseExchange.future;
                    }
                    if (scenario == 'exchange-logout') await logout();
                  }
                  if (!tokenRequest) {
                    accountRequests++;
                    if (accountRequests == 1 &&
                        scenario == 'retry-account-network') {
                      handler.reject(
                        DioException(
                          requestOptions: options,
                          type: DioExceptionType.connectionError,
                        ),
                      );
                      return;
                    }
                    if (accountRequests == 1 &&
                        scenario == 'retry-account-timeout') {
                      await releaseExchange.future;
                    }
                  }
                  handler.resolve(
                    Response(
                      requestOptions: options,
                      statusCode: scenario == 'exchange-failed' ? 400 : 200,
                      data: tokenRequest
                          ? tokens
                          : {'email': 'user@example.test'},
                    ),
                  );
                },
              ),
            );
            final auth = DropboxAuthService(
              store,
              dio: dio,
              launchBrowser: launch,
              requestTimeout: scenario.contains('timeout')
                  ? const Duration(milliseconds: 50)
                  : const Duration(seconds: 30),
            );
            await auth.initialize(clientId: 'client');
            logout = auth.signOut;
            login = () async => (await auth.signIn()).isSuccess();
          }
          try {
            if (scenario.startsWith('retry-cancel')) {
              final first = login();
              await firstLaunch.future;
              final cancelling = logout();
              final cancelExpectation = scenario == 'retry-cancel-failed'
                  ? expectLater(cancelling, throwsA(anything))
                  : cancelling;
              await deletionEntered.future;
              final second = login();
              if (scenario == 'retry-cancel-again') {
                unawaited(logout());
              }
              try {
                await Future<void>.delayed(const Duration(milliseconds: 50));
                expect(launches, 1);
              } finally {
                releaseDeletion.complete();
                await cancelExpectation;
              }
              expect(await first, isFalse);
              expect(
                await second.timeout(const Duration(seconds: 3)),
                scenario == 'retry-cancel',
              );
              if (scenario != 'retry-cancel') expect(await login(), isTrue);
            } else if (scenario == 'retry-late-token') {
              final first = login();
              await tokenStarted.future;
              await logout();
              expect(await first, isFalse);
              await browserRequest;
              expect(await login(), isTrue);
            } else if (scenario == 'retry-network' ||
                scenario.startsWith('retry-account-')) {
              expect(await login(), isFalse);
              await browserRequest;
              expect(await login(), isTrue);
            } else {
              expect(
                await login().timeout(const Duration(seconds: 3)),
                scenario == 'success',
              );
            }
          } finally {
            releaseExchange.complete();
          }
          await Future<void>.delayed(const Duration(milliseconds: 30));
          if (scenario.startsWith('retry-')) {
            verify(
              () => store.storeToken(
                key: any(named: 'key'),
                tokenData: any(named: 'tokenData'),
              ),
            ).called(1);
          }
          await cancellation;
          await browserRequest;
          expect(
            exchanges,
            (scenario == 'retry-network' ||
                    scenario == 'retry-late-token' ||
                    scenario.startsWith('retry-account-'))
                ? 2
                : scenario == 'success' ||
                      scenario.startsWith('retry-cancel') ||
                      scenario.startsWith('exchange-')
                ? 1
                : 0,
          );
          final rebound = await HttpServer.bind(
            InternetAddress.loopbackIPv4,
            Uri.parse(authorization.queryParameters['redirect_uri']!).port,
          );
          await rebound.close(force: true);
          if (scenario != 'success' && !scenario.startsWith('retry-')) {
            verifyNever(
              () => store.storeToken(
                key: any(named: 'key'),
                tokenData: any(named: 'tokenData'),
              ),
            );
          }
        },
      );
    }
  }
}
