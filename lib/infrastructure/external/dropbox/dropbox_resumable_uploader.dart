import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/dio_upload_cancellation.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_persistent_upload.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_upload_headers.dart';
import 'package:backup_database/infrastructure/external/upload_session_store.dart';
import 'package:dio/dio.dart';

class DropboxResumableUploader {
  const DropboxResumableUploader({this.contentClientFactory});

  final Dio Function(BaseOptions)? contentClientFactory;

  /// Upload em chunks via Dropbox `upload_session`.
  ///
  /// **Reescrito**: a versão anterior usava `fileStream.take(N).toList()`
  /// num loop, mas (1) `take` conta eventos do stream, não bytes, e
  /// (2) o stream de `openRead()` é single-subscription e fecha após o
  /// primeiro `take().toList()`. Resultado: a partir da 2ª iteração o
  /// stream estava fechado e o upload nunca completava para arquivos
  /// > 150 MB. Substituído por `RandomAccessFile.readInto` lendo a
  /// janela `[offset, offset+chunkSize)` em cada iteração.
  Future<Map<String, dynamic>> upload({
    required Dio dio,
    required File sourceFile,
    required String filePath,
    required int fileSize,
    String? accountId,
    String? contentHash,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (accountId != null && contentHash != null) {
      return DropboxPersistentUpload(
        UploadSessionStore(),
        contentClientFactory: contentClientFactory,
      ).upload(
        dio: dio,
        file: sourceFile,
        accountId: accountId,
        path: filePath,
        size: fileSize,
        hash: contentHash,
        isCancelled: isCancelled,
        onProgress: onProgress,
      );
    }
    UploadCancellation.throwIfCancelled(isCancelled);
    const dropboxChunkSize = UploadChunkConstants.dropboxResumableChunkSize;

    final options = BaseOptions(
      baseUrl: AppConstants.dropboxContentBaseUrl,
      connectTimeout: AppConstants.httpTimeout,
      receiveTimeout: AppConstants.httpTimeout,
      sendTimeout: AppConstants.httpTimeout,
      headers: dio.options.headers,
    );
    final contentDio = contentClientFactory?.call(options) ?? Dio(options);
    final cancellation = DioUploadCancellation(isCancelled);

    RandomAccessFile? raf;
    try {
      raf = await sourceFile.open();
      String? sessionId;
      var offset = 0;
      Map<String, dynamic>? lastResponseData;

      while (offset < fileSize) {
        UploadCancellation.throwIfCancelled(isCancelled);

        final remaining = fileSize - offset;
        final bytesToRead = remaining < dropboxChunkSize
            ? remaining
            : dropboxChunkSize;
        final buffer = Uint8List(bytesToRead);
        var totalRead = 0;
        while (totalRead < bytesToRead) {
          final n = await raf.readInto(buffer, totalRead, bytesToRead);
          if (n <= 0) {
            throw StateError(
              'Leitura interrompida em $offset+$totalRead/$bytesToRead bytes '
              '(arquivo encolheu durante upload?)',
            );
          }
          totalRead += n;
        }

        UploadCancellation.throwIfCancelled(isCancelled);
        final isFirst = offset == 0;
        final isLast = offset + bytesToRead == fileSize;
        final bytesUploadedBefore = offset;
        final progressCallback = onProgress == null
            ? null
            : (int sent, int total) {
                if (fileSize > 0) {
                  onProgress((bytesUploadedBefore + sent) / fileSize);
                }
              };

        if (isFirst && isLast) {
          // Arquivo cabe num único chunk dentro do limite resumable
          // (fileSize >= dropboxSimpleUploadLimit mas <= chunk size).
          // Sobe start + finish numa só chamada usando `close: true`
          // + finish separado — Dropbox exige finish para criar o
          // arquivo final.
          final startResponse = await contentDio.post(
            '/2/files/upload_session/start',
            cancelToken: cancellation.token,
            data: buffer,
            onSendProgress: progressCallback,
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Dropbox-API-Arg': '{"close": true}',
              },
            ),
          );
          sessionId =
              (startResponse.data as Map<String, dynamic>)['session_id']
                  as String;
          offset += bytesToRead;
          lastResponseData = await _finishUploadSession(
            contentDio: contentDio,
            cancelToken: cancellation.token,
            isCancelled: isCancelled,
            sessionId: sessionId,
            offset: offset,
            filePath: filePath,
            fileSize: fileSize,
            bytesUploadedBefore: offset,
            onProgress: onProgress,
          );
        } else if (isFirst) {
          final response = await contentDio.post(
            '/2/files/upload_session/start',
            cancelToken: cancellation.token,
            data: buffer,
            onSendProgress: progressCallback,
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Dropbox-API-Arg': '{"close": false}',
              },
            ),
          );
          sessionId =
              (response.data as Map<String, dynamic>)['session_id'] as String;
          offset += bytesToRead;
        } else if (!isLast) {
          const maxChunkAttempts = 3;
          var confirmedOffset = offset;
          for (var attempt = 1; ; attempt++) {
            UploadCancellation.throwIfCancelled(isCancelled);
            try {
              await contentDio.post(
                '/2/files/upload_session/append_v2',
                cancelToken: cancellation.token,
                data: Uint8List.sublistView(buffer, confirmedOffset - offset),
                onSendProgress: onProgress == null
                    ? null
                    : (sent, total) {
                        onProgress((confirmedOffset + sent) / fileSize);
                      },
                options: Options(
                  headers: {
                    'Content-Type': 'application/octet-stream',
                    'Dropbox-API-Arg': encodeDropboxUploadArguments({
                      'cursor': {
                        'session_id': sessionId,
                        'offset': confirmedOffset,
                      },
                      'close': false,
                    }),
                  },
                ),
              );
              break;
            } on DioException catch (error) {
              final data = error.response?.data;
              final detail = data is Map ? data['error'] : null;
              if (attempt > 1 &&
                  error.response?.statusCode == 409 &&
                  detail is Map &&
                  detail['.tag'] == 'incorrect_offset') {
                final remoteOffset = detail['correct_offset'];
                if (remoteOffset == offset + bytesToRead) break;
                if (remoteOffset is int &&
                    remoteOffset > confirmedOffset &&
                    remoteOffset < offset + bytesToRead &&
                    attempt < maxChunkAttempts) {
                  confirmedOffset = remoteOffset;
                  continue;
                }
              }
              final retryable =
                  error.type == DioExceptionType.connectionError ||
                  error.type == DioExceptionType.connectionTimeout ||
                  error.type == DioExceptionType.sendTimeout ||
                  error.type == DioExceptionType.receiveTimeout;
              if (!retryable || attempt >= maxChunkAttempts) rethrow;
            }
          }
          offset += bytesToRead;
        } else {
          // Último chunk + finish em uma só chamada
          lastResponseData = await _finishUploadSession(
            contentDio: contentDio,
            cancelToken: cancellation.token,
            isCancelled: isCancelled,
            sessionId: sessionId!,
            offset: offset,
            filePath: filePath,
            fileSize: fileSize,
            bytesUploadedBefore: bytesUploadedBefore,
            onProgress: onProgress,
            chunkData: buffer,
          );
          offset += bytesToRead;
        }
      }

      if (lastResponseData == null) {
        throw const DropboxFailure(
          message: 'Upload resumable Dropbox encerrou sem resposta de finish.',
        );
      }
      if (cancellation.token.isCancelled) {
        throw const UploadCancelledException();
      }
      UploadCancellation.throwIfCancelled(isCancelled);
      return lastResponseData;
    } finally {
      cancellation.dispose();
      contentDio.close(force: true);
      try {
        await raf?.close();
      } on Object catch (e, s) {
        LoggerService.debug('Dropbox RAF close: $e', e, s);
      }
    }
  }

  /// Commits to the same path on retry; never creates an autorenamed copy.
  Future<Map<String, dynamic>> _finishUploadSession({
    required Dio contentDio,
    required CancelToken cancelToken,
    required bool Function()? isCancelled,
    required String sessionId,
    required int offset,
    required String filePath,
    required int fileSize,
    required int bytesUploadedBefore,
    required UploadProgressCallback? onProgress,
    Uint8List? chunkData,
  }) async {
    final body = chunkData ?? Uint8List(0);
    final progressCallback = onProgress == null
        ? null
        : (int sent, int total) {
            if (fileSize > 0) {
              onProgress((bytesUploadedBefore + sent) / fileSize);
            }
          };

    UploadCancellation.throwIfCancelled(isCancelled);
    final response = await contentDio.post(
      '/2/files/upload_session/finish',
      cancelToken: cancelToken,
      data: body,
      onSendProgress: progressCallback,
      options: Options(
        headers: {
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': encodeDropboxUploadArguments({
            'cursor': {'session_id': sessionId, 'offset': offset},
            'commit': dropboxUploadCommit(filePath),
          }),
        },
      ),
    );
    return response.data as Map<String, dynamic>;
  }
}
