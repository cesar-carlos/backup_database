import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/dio_upload_cancellation.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_upload_headers.dart';
import 'package:dio/dio.dart';

class DropboxSimpleUploader {
  const DropboxSimpleUploader({this.contentClientFactory});

  final Dio Function(BaseOptions)? contentClientFactory;

  Future<Map<String, dynamic>> upload({
    required Dio dio,
    required File sourceFile,
    required String filePath,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    UploadCancellation.throwIfCancelled(isCancelled);
    final options = BaseOptions(
      baseUrl: AppConstants.dropboxContentBaseUrl,
      connectTimeout: AppConstants.httpTimeout,
      receiveTimeout: AppConstants.httpTimeout,
      sendTimeout: AppConstants.httpTimeout,
      headers: dio.options.headers,
    );
    final contentDio = contentClientFactory?.call(options) ?? Dio(options);
    final cancellation = DioUploadCancellation(isCancelled);

    try {
      final response = await contentDio.post(
        '/2/files/upload',
        cancelToken: cancellation.token,
        data: sourceFile.openRead().map((chunk) {
          UploadCancellation.throwIfCancelled(isCancelled);
          return chunk;
        }),
        onSendProgress: onProgress == null
            ? null
            : (sent, total) {
                if (total > 0) onProgress(sent / total);
              },
        options: Options(
          headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Length': await sourceFile.length(),
            'Dropbox-API-Arg': encodeDropboxUploadArguments(
              dropboxUploadCommit(filePath),
            ),
          },
        ),
      );
      if (cancellation.token.isCancelled) throw const UploadCancelledException();
      UploadCancellation.throwIfCancelled(isCancelled);
      return response.data as Map<String, dynamic>;
    } finally {
      cancellation.dispose();
      contentDio.close(force: true);
    }
  }
}
