import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/infrastructure/external/dio_upload_cancellation.dart';
import 'package:dio/dio.dart';

class DropboxUploadRecovery {
  const DropboxUploadRecovery();

  Future<Map<String, dynamic>?> findCompletedUpload({
    required Dio dio,
    required String filePath,
    required int fileSize,
    required String contentHash,
    bool Function()? isCancelled,
  }) async {
    UploadCancellation.throwIfCancelled(isCancelled);
    final cancellation = DioUploadCancellation(isCancelled);
    try {
      final response = await dio.post<dynamic>(
        '/2/files/get_metadata',
        data: {'path': filePath},
        cancelToken: cancellation.token,
      );
      UploadCancellation.throwIfCancelled(isCancelled);
      final metadata = response.data;
      if (metadata is! Map<String, dynamic> ||
          metadata['.tag'] != 'file' ||
          metadata['id'] is! String ||
          (metadata['id'] as String).isEmpty ||
          metadata['size'] is! int ||
          metadata['content_hash'] is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(
            metadata['content_hash'] as String,
          )) {
        throw const DropboxFailure(
          message: 'Não foi possível validar o arquivo existente no Dropbox.',
          code: FailureCodes.integrityValidationInconclusive,
        );
      }
      return metadata['size'] == fileSize &&
              (metadata['content_hash'] as String).toLowerCase() ==
                  contentHash.toLowerCase()
          ? metadata
          : null;
    } on DioException catch (error) {
      UploadCancellation.throwIfCancelled(isCancelled);
      final data = error.response?.data;
      final detail = data is Map ? data['error'] : null;
      final path = detail is Map ? detail['path'] : null;
      if (error.response?.statusCode == 409 &&
          detail is Map &&
          detail['.tag'] == 'path' &&
          path is Map &&
          path['.tag'] == 'not_found') {
        return null;
      }
      rethrow;
    } finally {
      cancellation.dispose();
    }
  }
}
