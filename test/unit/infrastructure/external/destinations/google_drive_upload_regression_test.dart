// Mock authentication is isolated from the HTTP protocol exercised below.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_auth_client.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_folder_ops.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_upload_client.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_uploader.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';
import 'package:backup_database/infrastructure/external/upload_session_store.dart';
import 'package:backup_database/infrastructure/security/machine_scope_secure_credential_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _AuthService extends Mock implements GoogleAuthService {}

class _Auth extends GoogleDriveAuthClient {
  _Auth() : super(_AuthService());
  final shared = AuthenticatedHttpClient('token');
  @override
  Future<rd.Result<GoogleDriveClientSession>> getAuthenticatedClient() async =>
      rd.Success(
        GoogleDriveClientSession(client: shared, accessToken: 'token'),
      );
  @override
  Future<T> executeWithTokenRefresh<T>(Future<T> Function() operation) =>
      operation();
}

class _Transport extends MockClient {
  _Transport(super.fn);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

http.Response _json(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  for (final renewing in [false, true]) {
    for (final connectionFailure in [false, true]) {
      test(
        'cancels pending authentication, renewal=$renewing failure=$connectionFailure',
        () async {
          final temp = await Directory.systemTemp.createTemp(
            'drive_auth_cancel_',
          );
          addTearDown(() => temp.delete(recursive: true));
          final source = await File('${temp.path}/backup.bak')
              .writeAsBytes([1, 2]);
          final service = _AuthService();
          final pending = Completer<rd.Result<GoogleAuthResult>>();
          final entered = Completer<void>();
          const credentials = GoogleAuthResult(
            accessToken: 'token',
            email: 'test@example.test',
          );
          when(service.signInSilently).thenAnswer((_) {
            if (renewing) return Future.value(const rd.Success(credentials));
            if (!entered.isCompleted) entered.complete();
            return pending.future;
          });
          when(() => service.signInSilently(forceRefresh: true))
              .thenAnswer((_) {
                entered.complete();
                return pending.future;
              });
          final auth = GoogleDriveAuthClient(service);
          var cancelled = false;
          var clientsCreated = 0;
          final uploader = GoogleDriveUploader(
            auth,
            GoogleDriveFolderOps(auth),
            clientFactory: () {
              clientsCreated++;
              return MockClient(
                (_) async => _json({
                  'error': {'code': 401, 'message': 'expired'},
                }, 401),
              );
            },
          );
          final upload = uploader.upload(
            sourceFilePath: source.path,
            config: const GoogleDriveDestinationConfig(
              folderId: 'root',
              folderName: 'Backups',
              accessToken: '',
              refreshToken: '',
            ),
            isCancelled: () => cancelled,
          );
          await entered.future;
          Future<String>? concurrentOperation;
          if (renewing && !connectionFailure) {
            var attempts = 0;
            concurrentOperation = auth.executeWithTokenRefresh(() async {
              if (attempts++ == 0) {
                throw drive.DetailedApiRequestError(401, 'expired');
              }
              return 'recovered';
            });
          }
          cancelled = true;
          final result = await upload.timeout(const Duration(seconds: 2));
          expect(result.exceptionOrNull(), UploadCancellation.cancelledFailure);
          final previousClients = clientsCreated;
          // A later operation may reset the UI cancellation flag.
          cancelled = false;
          if (connectionFailure) {
            pending.completeError(
              const SocketException('late connection failure'),
            );
          } else {
            pending.complete(const rd.Success(credentials));
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
          expect(clientsCreated, previousClients);
          expect(clientsCreated, renewing ? 1 : 0);
          if (concurrentOperation != null) {
            expect(await concurrentOperation, 'recovered');
            verify(() => service.signInSilently(forceRefresh: true)).called(1);
          }
          if (!connectionFailure) {
            final session = await auth.getAuthenticatedClient();
            session.getOrNull()?.client.close();
          }
        },
      );
    }
  }

  test('late response body cannot continue a timed out operation', () async {
    final body = StreamController<List<int>>();
    final entered = Completer<void>();
    final finished = Completer<void>();
    var continued = false;
    final transport = MockClient.streaming((request, stream) async {
      entered.complete();
      return http.StreamedResponse(body.stream, 200);
    });
    final client = GoogleDriveUploadClient(transport, 'token');
    final run = client.run(() async {
      try {
        await client.get(Uri.https('example.test', '/metadata'));
        continued = true;
      } finally {
        finished.complete();
      }
    }, idleTimeout: const Duration(milliseconds: 150));
    await entered.future;
    await expectLater(run, throwsA(isA<TimeoutException>()));
    body.add(utf8.encode('{"id":"late"}'));
    await body.close();
    await finished.future;
    expect(continued, isFalse);
  });

  test(
    'folder retry refreshes once and uses a newly authenticated API',
    () async {
      final service = _AuthService();
      var token = 'expired';
      var refreshes = 0;
      when(service.signInSilently).thenAnswer(
        (_) async => rd.Success(
          GoogleAuthResult(accessToken: token, email: 'test@example.test'),
        ),
      );
      when(() => service.signInSilently(forceRefresh: true))
          .thenAnswer((_) async {
            refreshes++;
            token = 'renewed';
            return rd.Success(
              GoogleAuthResult(accessToken: token, email: 'test@example.test'),
            );
          });
      final auth = GoogleDriveAuthClient(service);
      final tokens = <String>[];
      final result = await auth.executeWithTokenRefresh(() async {
        final session = (await auth.getAuthenticatedClient()).getOrThrow();
        addTearDown(session.client.close);
        final transport = MockClient((request) async {
          tokens.add(request.headers['Authorization']!);
          if (request.headers['Authorization'] == 'Bearer expired') {
            return _json({
              'error': {'code': 401, 'message': 'expired'},
            }, 401);
          }
          return _json({
            'files': [
              {'id': 'existing-folder'},
            ],
          });
        });
        final client = GoogleDriveUploadClient(transport, session.accessToken);
        return client.run(
          () => GoogleDriveFolderOps(auth).getOrCreateFolder(
            'Backups',
            'root',
            api: drive.DriveApi(client),
          ),
          idleTimeout: const Duration(seconds: 5),
        );
      });
      expect(result, 'existing-folder');
      expect(tokens, ['Bearer expired', 'Bearer renewed']);
      expect(refreshes, 1);
    },
  );

  for (final cancel in [false, true]) {
    test(
      'late response cannot continue interrupted operation, cancel=$cancel',
      () async {
        final response = Completer<http.Response>();
        final entered = Completer<void>();
        final finished = Completer<void>();
        var cancelled = false;
        var continued = false;
        final client = GoogleDriveUploadClient(
          _Transport((_) {
            entered.complete();
            return response.future;
          }),
          'token',
        );
        final run = client.run(
          () async {
            try {
              await client.get(Uri.https('example.test', '/metadata'));
              continued = true;
            } finally {
              finished.complete();
            }
          },
          idleTimeout: const Duration(milliseconds: 150),
          isCancelled: () => cancelled,
        );
        await entered.future;
        cancelled = cancel;
        await expectLater(
          run,
          throwsA(
            cancel ? isA<UploadCancelledException>() : isA<TimeoutException>(),
          ),
        );
        response.complete(_json({'id': 'late'}));
        await finished.future;
        expect(continued, isFalse);
      },
    );
  }

  const config = GoogleDriveDestinationConfig(
    folderId: 'root',
    folderName: "Empresa d'Água",
    accessToken: '',
    refreshToken: '',
  );
  for (final scenario in [
    'success',
    'lost',
    'missing',
    'corrupt',
    'cancel',
    'large',
    'rate',
    'forbidden',
    'metadata-recovery',
    'restarted',
    'recovery-missing',
    'recovery-different',
  ]) {
    test(
      'Drive upload $scenario uses stable ID and validates before success',
      () async {
        final temp = await Directory.systemTemp.createTemp('drive_upload_');
        addTearDown(() => temp.delete(recursive: true));
        final bytes = List<int>.filled(
          scenario == 'large' ? 6 * 1024 * 1024 : 32,
          7,
        );
        final file = await File('${temp.path}/backup.bak').writeAsBytes(bytes);
        FlutterSecureStorage.setMockInitialValues({});
        final digest = md5.convert(bytes).toString();
        final auth = _Auth();
        addTearDown(auth.shared.close);
        final clients = <_Transport>[];
        var posts = 0;
        var chunks = 0;
        var deleted = 0;
        var generated = 0;
        var cancelled = false;
        var queriedFolder = false;
        Object metadata() => {
          'id': 'stable-id',
          'name': 'backup.bak',
          'size': '${bytes.length}',
          if (scenario != 'missing')
            'md5Checksum': scenario == 'corrupt' ? '0' * 32 : digest,
        };
        Future<http.Response> handle(http.Request request) async {
          expect(request.headers['Authorization'], 'Bearer token');
          if (request.url.path.endsWith('/about')) {
            return _json({
              'user': {'permissionId': 'account'},
            });
          }
          if (request.url.path.endsWith('/generateIds')) {
            generated++;
            return _json({
              'ids': ['stable-id'],
            });
          }
          if (request.method == 'GET' &&
              request.url.queryParameters.containsKey('q')) {
            if (request.url.queryParameters['q']!.contains('mimeType !=')) {
              if (scenario.startsWith('recovery-') || scenario == 'restarted') {
                return _json({
                  'files': [
                    {
                      'id': 'previous-id',
                      'name': 'backup.bak',
                      'size': '${bytes.length}',
                      if (scenario != 'recovery-missing')
                        'md5Checksum': scenario == 'recovery-different'
                            ? '0' * 32
                            : digest,
                    },
                  ],
                });
              }
              return _json({'files': <Object>[]});
            }
            if (!queriedFolder) {
              expect(
                request.url.queryParameters['q'],
                contains(r"Empresa d\'Água"),
              );
              queriedFolder = true;
            }
            return _json({
              'files': [
                {'id': 'folder'},
              ],
            });
          }
          if (request.method == 'DELETE') {
            deleted++;
            return http.Response('', 204);
          }
          if (request.method == 'GET') return _json(metadata());
          if (request.method == 'PUT') {
            chunks++;
            final range = request.headers['content-range']!;
            final end = int.parse(
              RegExp(r'-(\d+)/').firstMatch(range)!.group(1)!,
            );
            if (end + 1 < bytes.length) {
              return http.Response('', 308, headers: {'range': 'bytes=0-$end'});
            }
            return _json(metadata());
          }
          posts++;
          expect(request.body, contains('stable-id'));
          if (scenario == 'forbidden' || (scenario == 'rate' && posts == 1)) {
            return _json({
              'error': {
                'code': 403,
                'message': scenario == 'rate'
                    ? 'userRateLimitExceeded'
                    : 'permissionDenied',
              },
            }, 403);
          }
          if (scenario == 'metadata-recovery') {
            return _json({'id': 'stable-id'});
          }
          if (scenario == 'large') {
            expect(request.url.queryParameters['uploadType'], 'resumable');
            return http.Response(
              '',
              200,
              headers: {
                'location': 'https://www.googleapis.com/upload/drive/v3/files?upload_id=session',
              },
            );
          }
          if (scenario == 'lost') {
            if (posts == 1) {
              throw const SocketException('response lost after commit');
            }
            return _json({
              'error': {'code': 409, 'message': 'exists'},
            }, 409);
          }
          if (scenario == 'cancel') cancelled = true;
          return _json(metadata());
        }

        final uploader = GoogleDriveUploader(
          auth,
          GoogleDriveFolderOps(auth),
          retryDelay: Duration.zero,
          sessionStore: UploadSessionStore(
            directory: temp,
            credentials: MachineScopeSecureCredentialService(
              secretsDirectory: temp,
            ),
          ),
          clientFactory: () {
            final client = _Transport(handle);
            clients.add(client);
            return client;
          },
        );
        final result = await uploader.upload(
          sourceFilePath: file.path,
          config: config,
          isCancelled: () => cancelled,
          maxRetries: 2,
        );
        expect(
          generated,
          scenario == 'restarted' || scenario == 'recovery-missing' ? 0 : 1,
        );
        expect(clients.every((client) => client.closed), isTrue);
        if (scenario == 'restarted') {
          expect(result.getOrThrow().fileId, 'previous-id');
          expect(posts, 0);
          expect(deleted, 0);
        } else if (scenario == 'recovery-missing') {
          expect(result.isError(), isTrue);
          expect(posts, 0);
          expect(deleted, 0);
        } else if (scenario == 'forbidden') {
          expect(result.isError(), isTrue);
          expect(posts, 1);
        } else if (scenario == 'cancel') {
          expect(result.exceptionOrNull(), UploadCancellation.cancelledFailure);
          expect(posts, 1);
        } else if (scenario == 'corrupt' || scenario == 'missing') {
          expect(result.isError(), isTrue);
          final failure = result.exceptionOrNull()! as GoogleDriveFailure;
          expect(
            failure.code,
            scenario == 'corrupt'
                ? FailureCodes.integrityValidationFailed
                : FailureCodes.integrityValidationInconclusive,
          );
          expect(deleted, scenario == 'corrupt' ? 1 : 0);
        } else {
          expect(
            result.isSuccess(),
            isTrue,
            reason: '${result.exceptionOrNull()}',
          );
          expect(result.getOrThrow().fileId, 'stable-id');
          if (scenario == 'lost') expect(posts, 2);
          if (scenario == 'rate') expect(posts, 2);
          if (scenario == 'large') expect(chunks, 6);
        }
      },
    );
  }

  for (final cancel in [false, true]) {
    test('stalled request is aborted and closed, cancel=$cancel', () async {
      var cancelled = false;
      final transport = _Transport((_) => Completer<http.Response>().future);
      final client = GoogleDriveUploadClient(transport, 'token');
      final run = client.run(
        () => client.get(Uri.https('example.test', '/')),
        idleTimeout: const Duration(milliseconds: 150),
        isCancelled: () => cancelled,
      );
      if (cancel) cancelled = true;
      await expectLater(
        run,
        throwsA(
          cancel ? isA<UploadCancelledException>() : isA<TimeoutException>(),
        ),
      );
      expect(transport.closed, isTrue);
      await expectLater(
        client.get(Uri.https('example.test', '/late')),
        throwsA(isA<http.ClientException>()),
      );
    });
  }
}
