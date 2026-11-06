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
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
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
          if (request.url.path.endsWith('/generateIds')) {
            generated++;
            return _json({
              'ids': ['stable-id'],
            });
          }
          if (request.method == 'GET' &&
              request.url.queryParameters.containsKey('q')) {
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
              headers: {'location': 'https://www.googleapis.com/session'},
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
        expect(generated, 1);
        expect(clients.every((client) => client.closed), isTrue);
        if (scenario == 'forbidden') {
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
