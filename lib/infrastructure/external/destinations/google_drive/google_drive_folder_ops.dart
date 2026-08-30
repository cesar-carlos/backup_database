import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_auth_client.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:result_dart/result_dart.dart' as rd;

class GoogleDriveFolderOps {
  GoogleDriveFolderOps(this._authClient);
  final GoogleDriveAuthClient _authClient;

  Future<String> getOrCreateFolder(
    String folderName,
    String parentId,
  ) async {
    return _authClient.executeWithTokenRefresh(() async {
      final clientResult = await _authClient.getAuthenticatedClient();
      if (clientResult.isError()) {
        throw clientResult.exceptionOrNull()!;
      }

      final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);

      final query =
          "name = '$folderName' and '$parentId' in parents and "
          "mimeType = 'application/vnd.google-apps.folder' and trashed = false";

      final existing = await driveApi.files.list(
        q: query,
        spaces: 'drive',
      );

      if (existing.files != null && existing.files!.isNotEmpty) {
        return existing.files!.first.id!;
      }

      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId];

      final created = await driveApi.files.create(folder);
      return created.id!;
    });
  }

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

        return driveApi.files.list(
          q: query,
          spaces: 'drive',
          orderBy: 'modifiedTime desc',
          $fields: 'files(id, name, size, modifiedTime, mimeType)',
        );
      });

      return rd.Success(result.files ?? []);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao listar backups Google Drive', e, stackTrace);
      return rd.Failure(
        GoogleDriveFailure(message: 'Erro ao listar backups: $e'),
      );
    }
  }
}
