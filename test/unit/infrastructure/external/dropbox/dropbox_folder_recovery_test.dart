import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_client.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_folder_ops.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _Auth extends Mock implements DropboxAuthService {}

class _Client extends DropboxAuthClient {
  _Client(this.dio) : super(_Auth());
  final Dio dio;
  @override
  Future<rd.Result<Dio>> getAuthenticatedDio() async => rd.Success(dio);
  @override
  Future<T> executeWithTokenRefresh<T>(Future<T> Function() action) => action();
}

void main() {
  for (final mode in [
    'existing',
    'missing',
    'restricted',
    'timeout',
    'folder-race',
    'file-race',
    'late-file',
  ]) {
    test('should verify destination folder during recovery: $mode', () async {
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      var reads = 0;
      var creates = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            void reject(Object detail) => handler.reject(
              DioException(
                requestOptions: request,
                response: Response<dynamic>(
                  requestOptions: request,
                  statusCode: 409,
                  data: {'error': detail},
                ),
              ),
            );
            if (request.path.endsWith('/get_metadata')) {
              reads++;
              if (mode == 'existing' || reads > 1) {
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: request,
                    data: {
                      '.tag': mode == 'late-file' ? 'file' : 'folder',
                      'id': 'id:folder',
                    },
                  ),
                );
              } else if (mode == 'timeout') {
                handler.reject(
                  DioException(
                    requestOptions: request,
                    type: DioExceptionType.receiveTimeout,
                  ),
                );
              } else {
                reject({
                  '.tag': 'path',
                  'path': {
                    '.tag': mode == 'restricted'
                        ? 'restricted_content'
                        : 'not_found',
                  },
                });
              }
            } else {
              creates++;
              if (mode == 'missing') {
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: request,
                    data: {
                      'metadata': {'id': 'id:created'},
                    },
                  ),
                );
              } else {
                reject({
                  '.tag': 'path',
                  'path': {
                    '.tag': 'conflict',
                    'conflict': {
                      '.tag': mode == 'file-race' ? 'file' : 'folder',
                    },
                  },
                });
              }
            }
          },
        ),
      );
      final result = await DropboxFolderOps(_Client(dio))
          .getOrCreateFolder('/backups');
      expect(
        result.isSuccess(),
        ['existing', 'missing', 'folder-race'].contains(mode),
      );
      expect(
        creates,
        ['existing', 'restricted', 'timeout'].contains(mode) ? 0 : 1,
      );
      if (mode == 'folder-race' || mode == 'late-file') expect(reads, 2);
    });
  }
}
