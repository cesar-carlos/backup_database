import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/nextcloud_failure.dart';
import 'package:backup_database/core/utils/backup_artifact_utils.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:backup_database/core/utils/file_stream_utils.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_errors.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_folder_ops.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_http_client.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_integrity_verifier.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_webdav_utils.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class NextcloudUploader {
  NextcloudUploader(this._httpClient, this._folderOps, this._integrity);

  final NextcloudHttpClient _httpClient;
  final NextcloudFolderOps _folderOps;
  final NextcloudIntegrityVerifier _integrity;

  Future<rd.Result<NextcloudUploadResult>> upload({
    required String sourceFilePath,
    required NextcloudDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      LoggerService.info('Enviando para Nextcloud: ${config.serverUrl}');
      UploadCancellation.throwIfCancelled(isCancelled);

      final missingSource = await BackupArtifactUtils.missingSourceFileFailure(
        sourceFilePath,
      );
      if (missingSource != null) return rd.Failure(missingSource);
      final sourceFile = File(sourceFilePath);

      final password = EncryptionService.decrypt(config.appPassword);

      final dio = _httpClient.create(config: config, password: password);

      final baseFolderPath = NextcloudWebdavUtils.buildBaseFolderPath(
        remotePath: config.remotePath,
        folderName: config.folderName,
      );

      final dateFolderName = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final dateFolderPath = NextcloudWebdavUtils.joinRemote(
        baseFolderPath,
        dateFolderName,
      );

      final fileName = customFileName ?? p.basename(sourceFilePath);
      final fileSize = await sourceFile.length();
      final localSha256 = await FileHashUtils.computeSha256(sourceFile);
      UploadCancellation.throwIfCancelled(isCancelled);
      final remoteFilePath = NextcloudWebdavUtils.joinRemote(
        dateFolderPath,
        fileName,
      );

      Exception? lastError;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        UploadCancellation.throwIfCancelled(isCancelled);
        try {
          await _folderOps.ensureFolderExists(
            dio: dio,
            config: config,
            path: baseFolderPath,
          );
          await _folderOps.ensureFolderExists(
            dio: dio,
            config: config,
            path: dateFolderPath,
          );
          UploadCancellation.throwIfCancelled(isCancelled);

          final uploadUrl = NextcloudWebdavUtils.buildDavUrl(
            serverUrl: config.serverUrl,
            username: config.username,
            path: remoteFilePath,
          );

          final uploadStream =
              chunkedFileStream(
                sourceFile,
                UploadChunkConstants.httpUploadChunkSize,
              ).transform(
                StreamTransformer<List<int>, List<int>>.fromHandlers(
                  handleData: (data, sink) {
                    if (isCancelled != null && isCancelled()) {
                      sink.addError(const UploadCancelledException());
                      sink.close();
                      return;
                    }
                    sink.add(data);
                  },
                ),
              );

          final response = await dio.putUri(
            uploadUrl,
            data: uploadStream,
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
                'Content-Length': fileSize,
              },
            ),
          );

          if (response.statusCode != null &&
              response.statusCode! >= 200 &&
              response.statusCode! < 300) {
            final integrityResult = await _integrity.validateUploadedFile(
              dio: dio,
              uploadUrl: uploadUrl,
              fileSize: fileSize,
              localSha256: localSha256,
              enableStrongIntegrityValidation:
                  config.enableStrongIntegrityValidation,
              enableReadBackValidation: config.enableReadBackValidation,
            );
            if (integrityResult.isError()) {
              final failure = integrityResult.exceptionOrNull()!;
              try {
                await dio.deleteUri(uploadUrl);
              } on Object catch (deleteError, s) {
                LoggerService.warning(
                  'Erro ao deletar arquivo inválido no Nextcloud',
                  deleteError,
                  s,
                );
              }
              throw failure;
            }

            stopwatch.stop();
            return rd.Success(
              NextcloudUploadResult(
                remotePath: remoteFilePath,
                fileSize: fileSize,
                duration: stopwatch.elapsed,
              ),
            );
          }

          throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
          );
        } on UploadCancelledException {
          stopwatch.stop();
          LoggerService.info('Upload Nextcloud cancelado pelo usuário');
          return UploadCancellation.cancelledResult();
        } on Object catch (e) {
          // `addError(UploadCancelledException())` num stream
          // single-subscription chega aqui embrulhado em
          // `DioException` — propaga a sentinel pra fora via
          // `UploadCancellation.isCancellation`.
          if (UploadCancellation.isCancellation(e)) {
            stopwatch.stop();
            LoggerService.info('Upload Nextcloud cancelado pelo usuário');
            return UploadCancellation.cancelledResult();
          }
          lastError = e is Exception ? e : Exception(e.toString());
          LoggerService.warning(
            'Nextcloud: tentativa $attempt falhou: $e',
          );
          if (attempt < maxRetries) {
            await Future.delayed(const Duration(seconds: 5));
          }
        }
      }

      stopwatch.stop();
      if (lastError is NextcloudFailure) {
        return rd.Failure(lastError);
      }
      return rd.Failure(
        NextcloudFailure(
          message: NextcloudErrors.describe(lastError),
          originalError: lastError,
        ),
      );
    } on UploadCancelledException {
      stopwatch.stop();
      LoggerService.info('Upload Nextcloud cancelado pelo usuário');
      return UploadCancellation.cancelledResult();
    } on Object catch (e) {
      stopwatch.stop();
      if (e is NextcloudFailure) {
        return rd.Failure(e);
      }
      return rd.Failure(
        NextcloudFailure(
          message: NextcloudErrors.describe(e),
          originalError: e,
        ),
      );
    }
  }
}
