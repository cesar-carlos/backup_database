import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/dio_upload_cancellation.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_upload_headers.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_upload_recovery.dart';
import 'package:backup_database/infrastructure/external/upload_session_store.dart';
import 'package:dio/dio.dart';

class DropboxPersistentUpload {
  DropboxPersistentUpload(this.store, {this.contentClientFactory});
  final UploadSessionStore store;
  final Dio Function(BaseOptions)? contentClientFactory;
  static const int chunkSize = 4 * 1024 * 1024;

  Future<Map<String, dynamic>> upload({
    required Dio dio,
    required File file,
    required String accountId,
    required String path,
    required int size,
    required String hash,
    bool Function()? isCancelled,
    UploadProgressCallback? onProgress,
  }) => store.run(
    ['dropbox', accountId, path.toLowerCase(), size, hash],
    (
      checkpoint,
    ) async {
      bool cancellationRequested() =>
          checkpoint.isStopped || (isCancelled?.call() ?? false);
      UploadCancellation.throwIfCancelled(cancellationRequested);
      final cancellation = DioUploadCancellation(cancellationRequested);
      final options = BaseOptions(
        baseUrl: AppConstants.dropboxContentBaseUrl,
        headers: dio.options.headers,
        connectTimeout: AppConstants.httpTimeout,
        sendTimeout: AppConstants.httpTimeout,
        receiveTimeout: AppConstants.httpTimeout,
      );
      final content = contentClientFactory?.call(options) ?? Dio(options);
      RandomAccessFile? input;
      try {
        final existing = await const DropboxUploadRecovery()
            .findCompletedUpload(
              dio: dio,
              filePath: path,
              fileSize: size,
              contentHash: hash,
              isCancelled: cancellationRequested,
            );
        if (existing != null) {
          await checkpoint.clear();
          return existing;
        }
        final state = await checkpoint.read();
        if (state != null &&
            (state['session'] is! String ||
                (state['session'] as String).isEmpty)) {
          throw const FormatException('Checkpoint Dropbox sem sessão válida.');
        }
        var session = state?['session'] as String?;
        var offset = 0;
        Future<Response<dynamic>> post(
          String method,
          Map<String, Object?> args,
          Uint8List body,
        ) => content.post<dynamic>(
          '/2/files/upload_session/$method',
          data: body,
          cancelToken: cancellation.token,
          options: Options(
            headers: {
              'Content-Type': 'application/octet-stream',
              'Dropbox-API-Arg': encodeDropboxUploadArguments(args),
            },
          ),
        );
        if (session != null) {
          try {
            await post('append_v2', {
              'cursor': {'session_id': session, 'offset': 0},
              'close': false,
            }, Uint8List(0));
          } on DioException catch (error) {
            final data = error.response?.data;
            final detail = data is Map ? data['error'] : null;
            if (error.response?.statusCode != 409 || detail is! Map) rethrow;
            if (detail['.tag'] == 'incorrect_offset' &&
                detail['correct_offset'] is int) {
              offset = detail['correct_offset'] as int;
            } else if (detail['.tag'] == 'not_found' ||
                detail['.tag'] == 'closed') {
              session = null;
            } else {
              rethrow;
            }
          }
        }
        UploadCancellation.throwIfCancelled(cancellationRequested);
        if (offset < 0 || offset > size) {
          throw StateError('Offset Dropbox inválido.');
        }
        if (session == null) {
          final response = await post('start', {'close': false}, Uint8List(0));
          session = (response.data as Map)['session_id'] as String;
          if (session.isEmpty) throw StateError('Sessão Dropbox ausente.');
          await checkpoint.save({'session': session});
          offset = 0;
        }
        input = await file.open();
        await input.setPosition(offset);
        while (offset < size) {
          UploadCancellation.throwIfCancelled(cancellationRequested);
          final length = (size - offset).clamp(0, chunkSize);
          final bytes = Uint8List(length);
          var read = 0;
          while (read < length) {
            final count = await input.readInto(bytes, read, length);
            if (count == 0) throw StateError('Arquivo de origem foi alterado.');
            read += count;
          }
          await post('append_v2', {
            'cursor': {'session_id': session, 'offset': offset},
            'close': false,
          }, bytes);
          offset += length;
          onProgress?.call(offset / size);
        }
        UploadCancellation.throwIfCancelled(cancellationRequested);
        final response = await post('finish', {
          'cursor': {'session_id': session, 'offset': offset},
          'commit': dropboxUploadCommit(path),
        }, Uint8List(0));
        UploadCancellation.throwIfCancelled(cancellationRequested);
        final metadata = Map<String, dynamic>.from(response.data as Map);
        if (metadata['size'] != size ||
            metadata['content_hash'] != hash ||
            metadata['id'] is! String) {
          throw StateError('Integridade Dropbox não confirmada.');
        }
        await checkpoint.clear();
        return metadata;
      } finally {
        cancellation.dispose();
        content.close(force: true);
        await input?.close();
      }
    },
    resourceIdentity: ['dropbox', accountId, path.toLowerCase()],
    isCancelled: isCancelled,
  );
}
