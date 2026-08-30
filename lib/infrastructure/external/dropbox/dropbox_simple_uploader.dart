import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:dio/dio.dart';

class DropboxSimpleUploader {
  const DropboxSimpleUploader();

  Future<Map<String, dynamic>> upload({
    required Dio dio,
    required File sourceFile,
    required String filePath,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    UploadCancellation.throwIfCancelled(isCancelled);
    final contentDio = Dio(
      BaseOptions(
        baseUrl: AppConstants.dropboxContentBaseUrl,
        connectTimeout: AppConstants.httpTimeout,
        receiveTimeout: AppConstants.httpTimeout,
        headers: dio.options.headers,
      ),
    );

    try {
      final response = await contentDio.post(
        '/2/files/upload',
        data: sourceFile.openRead(),
        onSendProgress: onProgress != null
            ? (sent, total) {
                if (total > 0) {
                  onProgress(sent / total);
                }
              }
            : null,
        options: Options(
          headers: {
            'Content-Type': 'application/octet-stream',
            'Dropbox-API-Arg':
                '{"path": "$filePath", "mode": "add", "autorename": true}',
          },
        ),
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final errorData = e.response?.data as Map<String, dynamic>?;
        final error = errorData?['error'] as Map<String, dynamic>?;
        final errorTag = error?['.tag'] as String?;

        if (errorTag == 'path/conflict') {
          final response = await contentDio.post(
            '/2/files/upload',
            data: sourceFile.openRead(),
            onSendProgress: onProgress != null
                ? (sent, total) {
                    if (total > 0) {
                      onProgress(sent / total);
                    }
                  }
                : null,
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Dropbox-API-Arg': '{"path": "$filePath", "mode": "overwrite"}',
              },
            ),
          );

          return response.data as Map<String, dynamic>;
        }
      }
      rethrow;
    }
  }
}
