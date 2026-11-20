import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_persistent_upload.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_persistent_upload.dart';
import 'package:backup_database/infrastructure/external/upload_session_store.dart';
import 'package:backup_database/infrastructure/security/machine_scope_secure_credential_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _FailingStorage extends Mock implements ISecureCredentialService {}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);
  final Future<ResponseBody> Function(RequestOptions, Uint8List) handle;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = BytesBuilder();
    await requestStream?.forEach(bytes.add);
    return handle(options, bytes.takeBytes());
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));
  late Directory temp;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('persistent_upload_');
  });
  tearDown(() => temp.delete(recursive: true));
  UploadSessionStore restart() => UploadSessionStore(
    directory: temp,
    credentials: MachineScopeSecureCredentialService(secretsDirectory: temp),
  );

  for (final provider in ['drive', 'dropbox']) {
    for (final value in [null, '', 42]) {
      test(
        'should preserve malformed $provider checkpoint instead of opening a session: $value',
        () async {
          final identity = provider == 'drive'
              ? <Object>['drive', 'account', 'folder', 'backup', 3, 'hash']
              : <Object>['dropbox', 'account', '/backup', 3, 'hash'];
          final state = provider == 'drive'
              ? <String, dynamic>{'id': 'id', 'uri': value}
              : <String, dynamic>{'session': value};
          await restart().run(identity, (checkpoint) => checkpoint.save(state));
          final file = await File('${temp.path}/backup')
              .writeAsBytes([1, 2, 3]);
          var requests = 0;
          final httpClient = MockClient((_) async {
            requests++;
            return http.Response('', 500);
          });
          addTearDown(httpClient.close);
          final dio = Dio()
            ..httpClientAdapter = _Adapter(
              (_, _) async => ResponseBody.fromString(
                '{"error":{".tag":"path","path":{".tag":"not_found"}}}',
                409,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              ),
            );
          addTearDown(() => dio.close(force: true));
          final work = provider == 'drive'
              ? GoogleDrivePersistentUpload(restart()).upload(
                  client: httpClient,
                  api: drive.DriveApi(httpClient),
                  file: file,
                  accountId: 'account',
                  parentId: 'folder',
                  name: 'backup',
                  size: 3,
                  md5: 'hash',
                )
              : DropboxPersistentUpload(
                  restart(),
                  contentClientFactory: (options) =>
                      Dio(options)
                        ..httpClientAdapter = _Adapter((_, _) async {
                          requests++;
                          return ResponseBody.fromString('{}', 200);
                        }),
                ).upload(
                  dio: dio,
                  file: file,
                  accountId: 'account',
                  path: '/backup',
                  size: 3,
                  hash: 'hash',
                );
          await expectLater(work, throwsA(isA<FormatException>()));
          expect(requests, 0);
          expect(
            await restart().run(identity, (checkpoint) => checkpoint.read()),
            state,
          );
        },
      );
    }
  }

  for (final provider in ['drive', 'dropbox']) {
    test(
      'should not send file bytes when $provider checkpoint cannot be saved',
      () async {
        final credentials = _FailingStorage();
        when(() => credentials.containsKey(key: any(named: 'key')))
            .thenAnswer((_) async => const rd.Success(false));
        when(
          () => credentials.storeToken(
            key: any(named: 'key'),
            tokenData: any(named: 'tokenData'),
          ),
        ).thenAnswer(
          (_) async => const rd.Failure(StorageFailure(message: 'disk full')),
        );
        final store = UploadSessionStore(
          credentials: credentials,
          directory: temp,
        );
        final file = await File('${temp.path}/backup').writeAsBytes([1, 2, 3]);
        var bodyRequests = 0;
        final httpClient = MockClient((request) async {
          if (request.method != 'GET') bodyRequests++;
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/generateIds')
                  ? {
                      'ids': ['id'],
                    }
                  : {'files': <Object>[]},
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        addTearDown(httpClient.close);
        final dio = Dio()
          ..httpClientAdapter = _Adapter(
            (request, bytes) async => ResponseBody.fromString(
              jsonEncode({
                'error': {
                  '.tag': 'path',
                  'path': {'.tag': 'not_found'},
                },
              }),
              409,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            ),
          );
        addTearDown(() => dio.close(force: true));
        final operation = provider == 'drive'
            ? GoogleDrivePersistentUpload(store).upload(
                client: httpClient,
                api: drive.DriveApi(httpClient),
                file: file,
                accountId: 'account',
                parentId: 'folder',
                name: 'backup',
                size: 3,
                md5: 'hash',
              )
            : DropboxPersistentUpload(
                store,
                contentClientFactory: (options) => Dio(options)
                  ..httpClientAdapter = _Adapter((request, bytes) async {
                    if (bytes.isNotEmpty) bodyRequests++;
                    return ResponseBody.fromString(
                      '{"session_id":"secret"}',
                      200,
                      headers: {
                        Headers.contentTypeHeader: [Headers.jsonContentType],
                      },
                    );
                  }),
              ).upload(
                dio: dio,
                file: file,
                accountId: 'account',
                path: '/backup',
                size: 3,
                hash: 'hash',
              );
        await expectLater(operation, throwsA(isA<StorageFailure>()));
        expect(bodyRequests, 0);
      },
    );
  }

  test(
    'should reject a stored Google session URL outside the API host',
    () async {
      final identity = <Object>[
        'drive',
        'account',
        'folder',
        'backup',
        3,
        'hash',
      ];
      await restart().run(
        identity,
        (checkpoint) => checkpoint.save({
          'id': 'id',
          'uri': 'https://attacker.invalid/upload',
        }),
      );
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('', 500);
      });
      addTearDown(client.close);
      final file = await File('${temp.path}/backup').writeAsBytes([1, 2, 3]);
      await expectLater(
        GoogleDrivePersistentUpload(restart()).upload(
          client: client,
          api: drive.DriveApi(client),
          file: file,
          accountId: 'account',
          parentId: 'folder',
          name: 'backup',
          size: 3,
          md5: 'hash',
        ),
        throwsA(isA<StateError>()),
      );
      expect(requests, 0);
    },
  );

  for (final provider in ['drive', 'dropbox']) {
    for (final mode in [
      'lost-block',
      'cancel',
      'lost-finish',
      'expired',
      'corrupt',
      'invalid-offset',
    ]) {
      test(
        'should resume $provider from durable checkpoint after $mode',
        () async {
          final chunk = provider == 'drive'
              ? GoogleDrivePersistentUpload.chunkSize
              : DropboxPersistentUpload.chunkSize;
          final bytes = Uint8List.fromList(
            List.generate(chunk + 17, (i) => i % 251),
          );
          final file = await File('${temp.path}/backup').writeAsBytes(bytes);
          final hash = provider == 'drive'
              ? await FileHashUtils.computeMd5(file)
              : await FileHashUtils.computeDropboxContentHash(file);
          var remote = BytesBuilder(copy: false);
          var received = 0;
          var starts = 0;
          var interrupted = false;
          var cancelled = false;
          var committed = false;
          var probeCount = 0;
          Map<String, Object> metadata() => {
            'id': 'id:backup',
            'name': 'backup',
            '.tag': 'file',
            'size': provider == 'drive' ? '${bytes.length}' : bytes.length,
            if (provider == 'drive')
              'md5Checksum': mode == 'corrupt' ? '0' * 32 : hash,
            if (provider == 'dropbox')
              'content_hash': mode == 'corrupt' ? '0' * 64 : hash,
          };
          void accept(List<int> data) {
            expect(data, bytes.sublist(received, received + data.length));
            remote.add(data);
            received += data.length;
          }

          http.Response json(Object value, [int status = 200]) => http.Response(
            jsonEncode(value),
            status,
            headers: {'content-type': 'application/json'},
          );
          final httpClient = MockClient((request) async {
            if (request.url.queryParameters.containsKey('q')) {
              return json({
                'files': committed ? [metadata()] : <Object>[],
              });
            }
            if (request.url.path.endsWith('/generateIds')) {
              return json({
                'ids': ['id:backup'],
              });
            }
            if (request.method == 'POST') {
              starts++;
              return http.Response(
                '',
                200,
                headers: {
                  'location': 'https://www.googleapis.com/upload/drive/v3/files?upload_id=secret-session',
                },
              );
            }
            if (request.headers['content-range'] == 'bytes */${bytes.length}') {
              probeCount++;
              if (mode == 'expired') {
                received = 0;
                remote = BytesBuilder();
                return http.Response('', 404);
              }
              if (committed) return json(metadata());
              return http.Response(
                '',
                308,
                headers: {
                  'range':
                      'bytes=0-${mode == 'invalid-offset' ? bytes.length + 5 : received - 1}',
                },
              );
            }
            expect(
              request.headers['content-range'],
              startsWith('bytes $received-'),
            );
            accept(request.bodyBytes);
            if (!interrupted &&
                received < bytes.length &&
                mode != 'lost-finish' &&
                mode != 'corrupt') {
              interrupted = true;
              if (mode == 'cancel') {
                cancelled = true;
              } else {
                throw const SocketException('lost response');
              }
            }
            if (received == bytes.length) {
              committed = true;
              if (mode == 'lost-finish' && !interrupted) {
                interrupted = true;
                throw const SocketException('lost finish');
              }
              return json(metadata());
            }
            return http.Response(
              '',
              308,
              headers: {'range': 'bytes=0-${received - 1}'},
            );
          });
          addTearDown(httpClient.close);
          ResponseBody body(Object data, [int status = 200]) =>
              ResponseBody.fromString(
                jsonEncode(data),
                status,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
          final dio = Dio()
            ..httpClientAdapter = _Adapter(
              (request, _) async => committed
                  ? body(metadata())
                  : body({
                      'error': {
                        '.tag': 'path',
                        'path': {'.tag': 'not_found'},
                      },
                    }, 409),
            );
          addTearDown(() => dio.close(force: true));
          final adapter = _Adapter((request, data) async {
            final args =
                jsonDecode(request.headers['Dropbox-API-Arg'] as String) as Map;
            if (request.path.endsWith('/start')) {
              starts++;
              return body({'session_id': 'secret-session'});
            }
            if (request.path.endsWith('/finish')) {
              committed = true;
              if (mode == 'lost-finish' && !interrupted) {
                interrupted = true;
                throw DioException(
                  requestOptions: request,
                  type: DioExceptionType.receiveTimeout,
                );
              }
              return body(metadata());
            }
            if (data.isEmpty) {
              probeCount++;
              if (mode == 'expired') {
                received = 0;
                remote = BytesBuilder();
                return body({
                  'error': {'.tag': 'not_found'},
                }, 409);
              }
              return body({
                'error': {
                  '.tag': 'incorrect_offset',
                  'correct_offset': mode == 'invalid-offset'
                      ? bytes.length + 5
                      : received,
                },
              }, 409);
            }
            expect((args['cursor'] as Map)['offset'], received);
            accept(data);
            if (!interrupted && mode != 'lost-finish' && mode != 'corrupt') {
              interrupted = true;
              if (mode == 'cancel') {
                cancelled = true;
              } else {
                throw DioException(
                  requestOptions: request,
                  type: DioExceptionType.receiveTimeout,
                );
              }
            }
            return body({});
          });
          Future<Object> upload() async {
            if (provider == 'drive') {
              return GoogleDrivePersistentUpload(restart()).upload(
                client: httpClient,
                api: drive.DriveApi(httpClient),
                file: file,
                accountId: 'account',
                parentId: 'folder',
                name: 'backup',
                size: bytes.length,
                md5: hash,
                isCancelled: () => cancelled,
              );
            }
            return DropboxPersistentUpload(
              restart(),
              contentClientFactory: (options) =>
                  Dio(options)..httpClientAdapter = adapter,
            ).upload(
              dio: dio,
              file: file,
              accountId: 'account',
              path: '/backup',
              size: bytes.length,
              hash: hash,
              isCancelled: () => cancelled,
            );
          }

          await expectLater(upload(), throwsA(anything));
          cancelled = false;
          if (mode == 'corrupt' || mode == 'invalid-offset') {
            await expectLater(upload(), throwsA(anything));
          } else {
            await upload();
            expect(received, bytes.length);
            expect(remote.takeBytes(), bytes);
            expect(starts, mode == 'expired' ? 2 : 1);
            if (mode != 'lost-finish') {
              expect(probeCount, greaterThan(0));
            }
          }
          if (Platform.isWindows) {
            final blobs = await temp
                .list()
                .where((f) => f.path.endsWith('.bdsecret'))
                .toList();
            expect(blobs, isNotEmpty);
            for (final blob in blobs) {
              expect(
                latin1.decode(await File(blob.path).readAsBytes()),
                isNot(contains('secret-session')),
              );
            }
          }
        },
      );
    }
  }
}
