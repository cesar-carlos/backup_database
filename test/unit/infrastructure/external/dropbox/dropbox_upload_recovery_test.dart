import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_upload_recovery.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hash = 'a' * 64;
  for (final scenario in [
    'completed',
    'different-hash',
    'different-size',
    'missing-hash',
    'missing-id',
    'folder',
    'not-found',
    'permission',
    'timeout',
    'cancel',
  ]) {
    test('should reconcile completed upload safely: $scenario', () async {
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      var cancelled = false;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(request.path, '/2/files/get_metadata');
            expect(request.data, {'path': '/backup.bak'});
            if (scenario == 'timeout') {
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
              return;
            }
            if (scenario == 'not-found' || scenario == 'permission') {
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: request,
                    statusCode: 409,
                    data: {
                      'error': {
                        '.tag': 'path',
                        'path': {
                          '.tag': scenario == 'not-found'
                              ? 'not_found'
                              : 'restricted_content',
                        },
                      },
                    },
                  ),
                ),
              );
              return;
            }
            if (scenario == 'cancel') cancelled = true;
            handler.resolve(
              Response<dynamic>(
                requestOptions: request,
                data: {
                  '.tag': scenario == 'folder' ? 'folder' : 'file',
                  if (scenario != 'missing-id') 'id': 'id:committed',
                  'size': scenario == 'different-size' ? 3 : 4,
                  if (scenario != 'missing-hash')
                    'content_hash': scenario == 'different-hash'
                        ? 'b' * 64
                        : hash,
                },
              ),
            );
          },
        ),
      );
      final result = const DropboxUploadRecovery().findCompletedUpload(
        dio: dio,
        filePath: '/backup.bak',
        fileSize: 4,
        contentHash: hash,
        isCancelled: () => cancelled,
      );
      if (scenario == 'completed') {
        expect((await result)!['id'], 'id:committed');
        // A fresh recovery object does not depend on a previous session in RAM.
        expect(
          (await const DropboxUploadRecovery().findCompletedUpload(
            dio: dio,
            filePath: '/backup.bak',
            fileSize: 4,
            contentHash: hash,
          ))!['id'],
          'id:committed',
        );
      } else if ([
        'not-found',
        'different-hash',
        'different-size',
      ].contains(scenario)) {
        expect(await result, isNull);
      } else if (scenario == 'cancel') {
        await expectLater(result, throwsA(isA<UploadCancelledException>()));
      } else if (scenario == 'permission' || scenario == 'timeout') {
        await expectLater(result, throwsA(isA<DioException>()));
      } else {
        await expectLater(result, throwsA(isA<DropboxFailure>()));
      }
    });
  }
}
