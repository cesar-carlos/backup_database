import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/utils/backup_artifact_utils.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_dropbox_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_client.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_errors.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_folder_ops.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_resumable_uploader.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_retention.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_simple_uploader.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class DropboxDestinationService implements IDropboxDestinationService {
  factory DropboxDestinationService(DropboxAuthService authService) {
    final authClient = DropboxAuthClient(authService);
    return DropboxDestinationService._(
      authClient,
      DropboxFolderOps(authClient),
      const DropboxSimpleUploader(),
      const DropboxResumableUploader(),
      DropboxRetention(authClient),
    );
  }

  DropboxDestinationService._(
    this._authClient,
    this._folderOps,
    this._simpleUploader,
    this._resumableUploader,
    this._retention,
  );

  final DropboxAuthClient _authClient;
  final DropboxFolderOps _folderOps;
  final DropboxSimpleUploader _simpleUploader;
  final DropboxResumableUploader _resumableUploader;
  final DropboxRetention _retention;

  @override
  Future<rd.Result<DropboxUploadResult>> upload({
    required String sourceFilePath,
    required DropboxDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      LoggerService.info('Enviando para Dropbox: ${config.folderName}');
      UploadCancellation.throwIfCancelled(isCancelled);

      final missingSource = await BackupArtifactUtils.missingSourceFileFailure(
        sourceFilePath,
      );
      if (missingSource != null) return rd.Failure(missingSource);
      final sourceFile = File(sourceFilePath);

      final mainFolderPath = config.folderPath.isEmpty
          ? '/${config.folderName}'
          : '${config.folderPath}/${config.folderName}';

      final mainFolderResult = await _folderOps.getOrCreateFolder(
        mainFolderPath,
      );
      if (mainFolderResult.isError()) {
        return rd.Failure(mainFolderResult.exceptionOrNull()!);
      }
      UploadCancellation.throwIfCancelled(isCancelled);

      final dateFolder = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final dateFolderPath = '$mainFolderPath/$dateFolder';
      final dateFolderResult = await _folderOps.getOrCreateFolder(
        dateFolderPath,
      );
      if (dateFolderResult.isError()) {
        return rd.Failure(dateFolderResult.exceptionOrNull()!);
      }
      UploadCancellation.throwIfCancelled(isCancelled);

      final fileName = customFileName ?? p.basename(sourceFilePath);
      final fileSize = await sourceFile.length();
      final localContentHash = await FileHashUtils.computeDropboxContentHash(
        sourceFile,
      );
      UploadCancellation.throwIfCancelled(isCancelled);
      final filePath = '$dateFolderPath/$fileName';

      await _folderOps.deleteFileIfExists(filePath);

      final useResumableUpload =
          fileSize >= AppConstants.dropboxSimpleUploadLimit;

      Exception? lastError;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        UploadCancellation.throwIfCancelled(isCancelled);
        try {
          final result = await _authClient.executeWithTokenRefresh(() async {
            final dioResult = await _authClient.getAuthenticatedDio();
            if (dioResult.isError()) {
              throw dioResult.exceptionOrNull()!;
            }

            final dio = dioResult.getOrNull()!;

            final uploadResult = useResumableUpload
                ? await _resumableUploader.upload(
                    dio: dio,
                    sourceFile: sourceFile,
                    filePath: filePath,
                    fileSize: fileSize,
                    onProgress: onProgress,
                    isCancelled: isCancelled,
                  )
                : await _simpleUploader.upload(
                    dio: dio,
                    sourceFile: sourceFile,
                    filePath: filePath,
                    onProgress: onProgress,
                    isCancelled: isCancelled,
                  );

            if (uploadResult.containsKey('size')) {
              final remoteSize = uploadResult['size'] as int;
              if (remoteSize != fileSize) {
                try {
                  await dio.post(
                    '/2/files/delete_v2',
                    data: {'path': filePath},
                  );
                } on Object catch (e, s) {
                  LoggerService.error(
                    'Falha ao remover arquivo corrompido do Dropbox: $filePath',
                    e,
                    s,
                  );
                }

                throw Exception(
                  'Arquivo corrompido no Dropbox. '
                  'Local: $fileSize, Remoto: $remoteSize',
                );
              }
            }

            final remoteContentHash = uploadResult['content_hash'] as String?;
            if (remoteContentHash == null || remoteContentHash.isEmpty) {
              throw DropboxFailure(
                message:
                    'Não foi possível confirmar integridade no Dropbox '
                    '(content_hash ausente).',
                code: FailureCodes.integrityValidationInconclusive,
                originalError: Exception('Dropbox content_hash ausente'),
              );
            }

            if (remoteContentHash.toLowerCase() !=
                localContentHash.toLowerCase()) {
              try {
                await dio.post(
                  '/2/files/delete_v2',
                  data: {'path': filePath},
                );
              } on Object catch (e, s) {
                LoggerService.error(
                  'Falha ao remover arquivo Dropbox com hash divergente: '
                  '$filePath',
                  e,
                  s,
                );
              }
              throw DropboxFailure(
                message:
                    'Falha de integridade no Dropbox: content_hash remoto '
                    'difere do arquivo local.',
                code: FailureCodes.integrityValidationFailed,
                originalError: Exception(
                  'Dropbox content_hash mismatch: '
                  'local=$localContentHash remote=$remoteContentHash',
                ),
              );
            }

            return uploadResult;
          });

          stopwatch.stop();

          return rd.Success(
            DropboxUploadResult(
              fileId: result['id'] as String,
              fileName: fileName,
              fileSize: fileSize,
              duration: stopwatch.elapsed,
            ),
          );
        } on UploadCancelledException {
          stopwatch.stop();
          LoggerService.info('Upload Dropbox cancelado pelo usuário');
          return UploadCancellation.cancelledResult();
        } on Object catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          LoggerService.warning('Dropbox: tentativa $attempt falhou: $e');

          if (attempt < maxRetries) {
            final delay = useResumableUpload
                ? AppConstants.retryDelay * 2
                : AppConstants.retryDelay;
            await Future.delayed(delay);
          }
        }
      }

      stopwatch.stop();
      if (lastError is DropboxFailure) {
        return rd.Failure(lastError);
      }
      return rd.Failure(
        DropboxFailure(
          message: DropboxErrors.describe(lastError),
          originalError: lastError,
        ),
      );
    } on UploadCancelledException {
      stopwatch.stop();
      LoggerService.info('Upload Dropbox cancelado pelo usuário');
      return UploadCancellation.cancelledResult();
    } on Object catch (e) {
      stopwatch.stop();
      if (e is DropboxFailure) {
        return rd.Failure(e);
      }
      return rd.Failure(
        DropboxFailure(
          message: DropboxErrors.describe(e),
          originalError: e,
        ),
      );
    }
  }

  @visibleForTesting
  static String getDropboxErrorMessage(Object? e) => DropboxErrors.describe(e);

  @override
  Future<rd.Result<bool>> testConnection(
    DropboxDestinationConfig config,
  ) async {
    try {
      final dioResult = await _authClient.getAuthenticatedDio();
      if (dioResult.isError()) {
        return rd.Failure(dioResult.exceptionOrNull()!);
      }

      final dio = dioResult.getOrNull()!;
      final mainFolderPath = config.folderPath.isEmpty
          ? '/${config.folderName}'
          : '${config.folderPath}/${config.folderName}';

      await _authClient.executeWithTokenRefresh(() async {
        final response = await dio.post(
          '/2/files/get_metadata',
          data: {'path': mainFolderPath},
        );
        return response.data;
      });

      return const rd.Success(true);
    } on Object catch (e, s) {
      LoggerService.error('Erro ao testar conexão com Dropbox', e, s);
      return rd.Failure(
        DropboxFailure(
          message: DropboxErrors.describe(e),
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<int>> cleanOldBackups({
    required DropboxDestinationConfig config,
  }) {
    return _retention.cleanOldBackups(config: config);
  }
}
