import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:dio/dio.dart';

class DropboxResumableUploader {
  const DropboxResumableUploader();

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
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    UploadCancellation.throwIfCancelled(isCancelled);
    const dropboxChunkSize = UploadChunkConstants.dropboxResumableChunkSize;

    final contentDio = Dio(
      BaseOptions(
        baseUrl: AppConstants.dropboxContentBaseUrl,
        connectTimeout: AppConstants.httpTimeout,
        receiveTimeout: AppConstants.httpTimeout,
        headers: dio.options.headers,
      ),
    );

    final raf = await sourceFile.open();
    try {
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
          await contentDio.post(
            '/2/files/upload_session/append_v2',
            data: buffer,
            onSendProgress: progressCallback,
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Dropbox-API-Arg':
                    '{"cursor": {"session_id": "$sessionId", "offset": $offset}, "close": false}',
              },
            ),
          );
          offset += bytesToRead;
        } else {
          // Último chunk + finish em uma só chamada
          lastResponseData = await _finishUploadSession(
            contentDio: contentDio,
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
      return lastResponseData;
    } finally {
      try {
        await raf.close();
      } on Object catch (e, s) {
        LoggerService.debug('Dropbox RAF close: $e', e, s);
      }
    }
  }

  /// Faz o `upload_session/finish` (com retry `mode: overwrite` quando
  /// Dropbox responde `path/conflict`).
  Future<Map<String, dynamic>> _finishUploadSession({
    required Dio contentDio,
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

    final commitOffset = chunkData == null ? offset : offset;

    Future<Map<String, dynamic>> doFinish({required bool overwrite}) async {
      final mode = overwrite ? '"overwrite"' : '"add", "autorename": true';
      final response = await contentDio.post(
        '/2/files/upload_session/finish',
        data: body,
        onSendProgress: progressCallback,
        options: Options(
          headers: {
            'Content-Type': 'application/octet-stream',
            'Dropbox-API-Arg':
                '{"cursor": {"session_id": "$sessionId", "offset": $commitOffset}, '
                '"commit": {"path": "$filePath", "mode": $mode}}',
          },
        ),
      );
      return response.data as Map<String, dynamic>;
    }

    try {
      return await doFinish(overwrite: false);
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final errorData = e.response?.data as Map<String, dynamic>?;
        final error = errorData?['error'] as Map<String, dynamic>?;
        final errorTag = error?['.tag'] as String?;
        if (errorTag == 'path/conflict') {
          return doFinish(overwrite: true);
        }
      }
      rethrow;
    }
  }
}
