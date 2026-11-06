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
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_upload_client.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class GoogleDriveUploader {
  GoogleDriveUploader(
    this._authClient,
    this._folderOps, {
    http.Client Function()? clientFactory,
    this.idleTimeout = const Duration(minutes: 2),
    this.retryDelay = AppConstants.retryDelay,
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  final Duration idleTimeout;
  final Duration retryDelay;

  Future<T> _withClient<T>(
    Future<T> Function(drive.DriveApi, GoogleDriveUploadClient) action,
    bool Function()? isCancelled,
  ) => _authClient.executeWithTokenRefresh(() async {
    UploadCancellation.throwIfCancelled(isCancelled);
    final session = (await _authClient.getAuthenticatedClient()).getOrThrow();
    UploadCancellation.throwIfCancelled(isCancelled);
    final client = GoogleDriveUploadClient(
      _clientFactory(),
      session.accessToken,
    );
    return client.run(
      () => action(drive.DriveApi(client), client),
      idleTimeout: idleTimeout,
      isCancelled: isCancelled,
    );
  });

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
      if (maxRetries < 1) throw ArgumentError.value(maxRetries, 'maxRetries');
      LoggerService.info('Enviando para Google Drive: ${config.folderName}');
      UploadCancellation.throwIfCancelled(isCancelled);

      final missingSource = await BackupArtifactUtils.missingSourceFileFailure(
        sourceFilePath,
      );
      if (missingSource != null) return rd.Failure(missingSource);
      final sourceFile = File(sourceFilePath);

      final mainFolderId = await _withClient(
        (api, _) => _folderOps.getOrCreateFolder(
          config.folderName,
          config.folderId,
          api: api,
        ),
        isCancelled,
      );
      UploadCancellation.throwIfCancelled(isCancelled);

      final dateFolder = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final dateFolderId = await _withClient(
        (api, _) => _folderOps.getOrCreateFolder(
          dateFolder,
          mainFolderId,
          api: api,
        ),
        isCancelled,
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

      final fileId = await _withClient((api, _) async {
        final ids = await api.files.generateIds(count: 1, space: 'drive');
        if (ids.ids == null || ids.ids!.length != 1) {
          throw const GoogleDriveFailure(
            message: 'Google Drive não retornou ID para o envio.',
          );
        }
        return ids.ids!.single;
      }, isCancelled);
      Exception? lastError;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        UploadCancellation.throwIfCancelled(isCancelled);
        try {
          LoggerService.debug('Tentativa $attempt de $maxRetries');

          final result = await _withClient((driveApi, client) async {
            final driveFile = drive.File()
              ..id = fileId
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
                  client.touch();
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

            drive.File uploadedFile;
            try {
              uploadedFile = await driveApi.files.create(
                driveFile,
                uploadMedia: media,
                uploadOptions: useResumableUpload
                    ? drive.ResumableUploadOptions()
                    : drive.UploadOptions.defaultOptions,
                $fields: 'id,name,size,md5Checksum',
              );
            } on drive.DetailedApiRequestError catch (e) {
              if (e.status != 409) rethrow;
              // A previous request may have committed before its response was lost.
              uploadedFile = await driveApi.files.get(
                fileId,
                $fields: 'id,name,size,md5Checksum',
              ) as drive.File;
            }
            UploadCancellation.throwIfCancelled(isCancelled);
            if (uploadedFile.id != fileId ||
                uploadedFile.size == null ||
                uploadedFile.md5Checksum == null ||
                uploadedFile.md5Checksum!.isEmpty) {
              uploadedFile = await driveApi.files.get(
                fileId,
                $fields: 'id,name,size,md5Checksum',
              ) as drive.File;
            }
            UploadCancellation.throwIfCancelled(isCancelled);
            if (uploadedFile.id != fileId ||
                uploadedFile.size == null ||
                uploadedFile.md5Checksum == null ||
                uploadedFile.md5Checksum!.isEmpty) {
              throw const GoogleDriveFailure(
                message: 'Não foi possível confirmar integridade no Google Drive (metadados ausentes).',
                code: FailureCodes.integrityValidationInconclusive,
              );
            }
            if (int.tryParse(uploadedFile.size!) != fileSize ||
                uploadedFile.md5Checksum!.toLowerCase() !=
                    localMd5.toLowerCase()) {
              try {
                await driveApi.files.delete(fileId);
              } on Object catch (e) {
                LoggerService.warning(
                  'Não foi possível remover arquivo com integridade inválida: $e',
                );
              }
              throw const GoogleDriveFailure(
                message: 'Falha de integridade no Google Drive: tamanho ou MD5 divergente.',
                code: FailureCodes.integrityValidationFailed,
              );
            }
            return uploadedFile;
          }, isCancelled);

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
          if (isCancelled?.call() ?? false) {
            return UploadCancellation.cancelledResult();
          }
          if (e is GoogleDriveFailure &&
              e.code == FailureCodes.integrityValidationFailed) {
            return rd.Failure(e);
          }
          if (e is drive.DetailedApiRequestError &&
              e.status != 429 &&
              e.status != 408 &&
              !(e.status == 403 &&
                  e.toString().toLowerCase().contains('ratelimit')) &&
              (e.status ?? 0) < 500) {
            rethrow;
          }
          lastError = e is Exception ? e : Exception(e.toString());
          LoggerService.warning('Tentativa $attempt falhou: $e');

          if (attempt < maxRetries) {
            final delay = useResumableUpload ? retryDelay * 2 : retryDelay;
            final waiting = Stopwatch()..start();
            while (waiting.elapsed < delay) {
              UploadCancellation.throwIfCancelled(isCancelled);
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
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
