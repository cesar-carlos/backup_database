import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/core/utils/backup_artifact_utils.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:backup_database/core/utils/file_stream_utils.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_google_drive_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_auth_client.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_errors.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_folder_ops.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class GoogleDriveUploader {
  GoogleDriveUploader(this._authClient, this._folderOps);

  final GoogleDriveAuthClient _authClient;
  final GoogleDriveFolderOps _folderOps;

  Future<rd.Result<GoogleDriveUploadResult>> upload({
    required String sourceFilePath,
    required GoogleDriveDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      LoggerService.info('Enviando para Google Drive: ${config.folderName}');
      UploadCancellation.throwIfCancelled(isCancelled);

      final missingSource = await BackupArtifactUtils.missingSourceFileFailure(
        sourceFilePath,
      );
      if (missingSource != null) return rd.Failure(missingSource);
      final sourceFile = File(sourceFilePath);

      final mainFolderId = await _folderOps.getOrCreateFolder(
        config.folderName,
        config.folderId,
      );
      UploadCancellation.throwIfCancelled(isCancelled);

      final dateFolder = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final dateFolderId = await _folderOps.getOrCreateFolder(
        dateFolder,
        mainFolderId,
      );
      UploadCancellation.throwIfCancelled(isCancelled);

      final fileName = customFileName ?? p.basename(sourceFilePath);
      final fileSize = await sourceFile.length();
      final localMd5 = await FileHashUtils.computeMd5(sourceFile);
      UploadCancellation.throwIfCancelled(isCancelled);

      const largeFileThreshold = 5 * 1024 * 1024;
      final useResumableUpload = fileSize > largeFileThreshold;

      if (useResumableUpload) {
        LoggerService.info(
          'Arquivo grande detectado (${ByteFormat.format(fileSize)}). Usando upload resumável.',
        );
      }

      Exception? lastError;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        UploadCancellation.throwIfCancelled(isCancelled);
        try {
          LoggerService.debug('Tentativa $attempt de $maxRetries');

          final result = await _authClient.executeWithTokenRefresh(() async {
            final clientResult = await _authClient.getAuthenticatedClient();
            if (clientResult.isError()) {
              throw clientResult.exceptionOrNull()!;
            }

            final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);

            final driveFile = drive.File()
              ..name = fileName
              ..parents = [dateFolderId];

            var fileStream = chunkedFileStream(
              sourceFile,
              UploadChunkConstants.httpUploadChunkSize,
            );

            var bytesSent = 0;
            fileStream = fileStream.transform(
              StreamTransformer<List<int>, List<int>>.fromHandlers(
                handleData: (data, sink) {
                  if (isCancelled != null && isCancelled()) {
                    sink.addError(const UploadCancelledException());
                    sink.close();
                    return;
                  }
                  final chunkLength = data.length;
                  bytesSent += chunkLength;
                  if (onProgress != null && fileSize > 0) {
                    onProgress(bytesSent / fileSize);
                  }
                  sink.add(data);
                },
              ),
            );

            final media = drive.Media(
              fileStream,
              fileSize,
            );

            final uploadedFile = await driveApi.files.create(
              driveFile,
              uploadMedia: media,
              $fields: 'id, name, size, md5Checksum',
            );

            if (uploadedFile.size != null) {
              final remoteSize = int.parse(uploadedFile.size!);
              if (remoteSize != fileSize) {
                try {
                  await driveApi.files.delete(uploadedFile.id!);
                } on Object catch (e) {
                  LoggerService.warning(
                    'Não foi possível remover arquivo corrompido: $e',
                  );
                }

                throw Exception(
                  'Arquivo corrompido no Google Drive. '
                  'Local: $fileSize, Remoto: $remoteSize',
                );
              }
            }

            final remoteMd5 = uploadedFile.md5Checksum;
            if (remoteMd5 == null || remoteMd5.isEmpty) {
              throw GoogleDriveFailure(
                message:
                    'Não foi possível confirmar integridade no Google Drive '
                    '(md5Checksum não retornado pela API).',
                code: FailureCodes.integrityValidationInconclusive,
                originalError: Exception('Google Drive md5Checksum ausente'),
              );
            }
            if (remoteMd5.toLowerCase() != localMd5.toLowerCase()) {
              try {
                await driveApi.files.delete(uploadedFile.id!);
              } on Object catch (e) {
                LoggerService.warning(
                  'Não foi possível remover arquivo com hash divergente: $e',
                );
              }
              throw GoogleDriveFailure(
                message:
                    'Falha de integridade no Google Drive: hash remoto difere '
                    'do arquivo local (MD5).',
                code: FailureCodes.integrityValidationFailed,
                originalError: Exception(
                  'Google Drive MD5 mismatch: local=$localMd5 remote=$remoteMd5',
                ),
              );
            }

            return uploadedFile;
          });

          stopwatch.stop();

          LoggerService.info(
            'Upload Google Drive concluído: ${result.id} (${ByteFormat.format(fileSize)} em ${stopwatch.elapsed.inSeconds}s)',
          );

          return rd.Success(
            GoogleDriveUploadResult(
              fileId: result.id!,
              fileName: fileName,
              fileSize: fileSize,
              duration: stopwatch.elapsed,
            ),
          );
        } on UploadCancelledException {
          stopwatch.stop();
          LoggerService.info('Upload Google Drive cancelado pelo usuário');
          return UploadCancellation.cancelledResult();
        } on Object catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          LoggerService.warning('Tentativa $attempt falhou: $e');

          if (attempt < maxRetries) {
            final delay = useResumableUpload
                ? AppConstants.retryDelay * 2
                : AppConstants.retryDelay;
            await Future.delayed(delay);
          }
        }
      }

      stopwatch.stop();
      if (lastError is GoogleDriveFailure) {
        return rd.Failure(lastError);
      }
      return rd.Failure(
        GoogleDriveFailure(
          message: GoogleDriveErrors.describe(lastError),
          originalError: lastError,
        ),
      );
    } on UploadCancelledException {
      stopwatch.stop();
      LoggerService.info('Upload Google Drive cancelado pelo usuário');
      return UploadCancellation.cancelledResult();
    } on Object catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('Erro no upload Google Drive', e, stackTrace);
      if (e is GoogleDriveFailure) {
        return rd.Failure(e);
      }
      return rd.Failure(
        GoogleDriveFailure(
          message: GoogleDriveErrors.describe(e),
          originalError: e,
        ),
      );
    }
  }
}
