import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_google_drive_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_auth_client.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_errors.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_folder_ops.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_retention.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_uploader.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:result_dart/result_dart.dart' as rd;

export 'google_drive/google_drive_auth_client.dart'
    show AuthenticatedHttpClient;

class GoogleDriveDestinationService implements IGoogleDriveDestinationService {
  factory GoogleDriveDestinationService(GoogleAuthService authService) {
    final authClient = GoogleDriveAuthClient(authService);
    final folderOps = GoogleDriveFolderOps(authClient);
    return GoogleDriveDestinationService._(
      authClient,
      folderOps,
      GoogleDriveUploader(authClient, folderOps),
      GoogleDriveRetention(authClient, folderOps),
    );
  }

  GoogleDriveDestinationService._(
    this._authClient,
    this._folderOps,
    this._uploader,
    this._retention,
  );

  final GoogleDriveAuthClient _authClient;
  final GoogleDriveFolderOps _folderOps;
  final GoogleDriveUploader _uploader;
  final GoogleDriveRetention _retention;

  @override
  Future<rd.Result<GoogleDriveUploadResult>> upload({
    required String sourceFilePath,
    required GoogleDriveDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) {
    return _uploader.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
      maxRetries: maxRetries,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  @visibleForTesting
  static String getGoogleDriveErrorMessage(Object? e) =>
      GoogleDriveErrors.describe(e);

  @override
  Future<rd.Result<bool>> testConnection(
    GoogleDriveDestinationConfig config,
  ) async {
    try {
      final clientResult = await _authClient.getAuthenticatedClient();
      if (clientResult.isError()) {
        return rd.Failure(clientResult.exceptionOrNull()!);
      }

      final clientData = clientResult.getOrNull()!;
      final driveApi = drive.DriveApi(clientData.client);

      await driveApi.files.get(
        config.folderId,
        $fields: 'id,name',
      );

      return const rd.Success(true);
    } on Object catch (e, s) {
      LoggerService.error('Erro ao testar conexão com Google Drive', e, s);
      return rd.Failure(
        GoogleDriveFailure(
          message: 'Erro ao conectar ao Google Drive: $e',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<int>> cleanOldBackups({
    required GoogleDriveDestinationConfig config,
  }) {
    return _retention.cleanOldBackups(config: config);
  }

  Future<rd.Result<List<drive.File>>> listBackups({
    required String folderId,
  }) {
    return _folderOps.listBackups(folderId: folderId);
  }
}
