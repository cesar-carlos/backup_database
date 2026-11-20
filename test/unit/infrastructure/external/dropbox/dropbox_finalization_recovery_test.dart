import 'dart:io';

import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_client.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_destination_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_folder_ops.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_resumable_uploader.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_retention.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_simple_uploader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _Auth extends Mock implements DropboxAuthService {}

class _Folders extends Mock implements DropboxFolderOps {}

class _Retention extends Mock implements DropboxRetention {}

class _Client extends DropboxAuthClient {
  _Client(this.dio) : super(_Auth());
  final Dio dio;
  @override
  Future<rd.Result<Dio>> getAuthenticatedDio() async => rd.Success(dio);
  @override
  Future<T> executeWithTokenRefresh<T>(Future<T> Function() operation) =>
      operation();
}

void main() {
  test('should recover a committed upload after losing response and recreating service', () async {
    final temp = await Directory.systemTemp.createTemp('dropbox_finalization_');
    addTearDown(() => temp.delete(recursive: true));
    final source = await File('${temp.path}/backup.bak')
        .writeAsBytes([1, 2, 3, 4]);
    final hash = await FileHashUtils.computeDropboxContentHash(source);
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    var committed = false;
    var uploads = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (!committed) {
            handler.reject(
              DioException(
                requestOptions: request,
                response: Response<dynamic>(
                  requestOptions: request,
                  statusCode: 409,
                  data: {
                    'error': {
                      '.tag': 'path',
                      'path': {'.tag': 'not_found'},
                    },
                  },
                ),
              ),
            );
          } else {
            handler.resolve(
              Response<dynamic>(
                requestOptions: request,
                data: {
                  '.tag': 'file',
                  'id': 'id:completed',
                  'size': 4,
                  'content_hash': hash,
                },
              ),
            );
          }
        },
      ),
    );
    final folders = _Folders();
    when(() => folders.getOrCreateFolder(any()))
        .thenAnswer((_) async => const rd.Success(()));
    DropboxDestinationService createService() =>
        DropboxDestinationService.withDependencies(
          _Client(dio),
          folders,
          DropboxSimpleUploader(
            contentClientFactory: (options) {
              final content = Dio(options);
              content.interceptors.add(
                InterceptorsWrapper(
                  onRequest: (request, handler) {
                    uploads++;
                    committed = true;
                    handler.reject(
                      DioException(
                        requestOptions: request,
                        type: DioExceptionType.receiveTimeout,
                      ),
                    );
                  },
                ),
              );
              return content;
            },
          ),
          const DropboxResumableUploader(),
          _Retention(),
        );
    const config = DropboxDestinationConfig(folderPath: '/backups');
    final first = await createService().upload(
      sourceFilePath: source.path,
      config: config,
      maxRetries: 1,
    );
    expect(first.isError(), isTrue);
    final second = await createService().upload(
      sourceFilePath: source.path,
      config: config,
      maxRetries: 1,
    );
    expect(second.isSuccess(), isTrue);
    expect(second.getOrNull()!.fileId, 'id:completed');
    expect(uploads, 1);
  });
}
