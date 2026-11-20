import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_auth_client.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_file_listing.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:result_dart/result_dart.dart' as rd;

class GoogleDriveFolderOps {
  GoogleDriveFolderOps(this._authClient);
  final GoogleDriveAuthClient _authClient;

  Future<String> getOrCreateFolder(
    String folderName,
    String parentId, {
    drive.DriveApi? api,
  }) async {
    Future<String> operation() async {
      var driveApi = api;
      if (driveApi == null) {
        final clientResult = await _authClient.getAuthenticatedClient();
        if (clientResult.isError()) {
          throw clientResult.exceptionOrNull()!;
        }
        driveApi = drive.DriveApi(clientResult.getOrNull()!.client);
      }

      final query =
          "name = '${_escape(folderName)}' and '${_escape(parentId)}' in parents and "
          "mimeType = 'application/vnd.google-apps.folder' and trashed = false";

      final existing = await listAllGoogleDriveFiles(
        driveApi,
        query: query,
        fields: 'id',
      );

      if (existing.isNotEmpty) {
        return existing.first.id!;
      }

      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId];

      final created = await driveApi.files.create(folder);
      return created.id!;
    }

    // An injected API belongs to the caller's token-refresh scope. Retrying
    // here would reuse its expired token even after refreshing credentials.
    return api == null
        ? _authClient.executeWithTokenRefresh(operation)
        : operation();
  }

  static String _escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  Future<rd.Result<List<drive.File>>> listBackups({
    required String folderId,
  }) async {
    try {
      final result = await _authClient.executeWithTokenRefresh(() async {
        final clientResult = await _authClient.getAuthenticatedClient();
        if (clientResult.isError()) {
          throw clientResult.exceptionOrNull()!;
        }

        final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);
        final query = "'$folderId' in parents and trashed = false";

        return listAllGoogleDriveFiles(
          driveApi,
          query: query,
          orderBy: 'modifiedTime desc',
          fields: 'id,name,size,modifiedTime,mimeType',
        );
      });

      return rd.Success(result);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao listar backups Google Drive', e, stackTrace);
      return rd.Failure(
        GoogleDriveFailure(message: 'Erro ao listar backups: $e'),
      );
    }
  }
}
